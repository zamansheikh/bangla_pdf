/// Parsed view of a TrueType/OpenType font: table directory, `cmap`, `hmtx`,
/// `GDEF`, and the `GSUB`/`GPOS` layout tables.
///
/// This is deliberately read-only and allocation-light. Nothing here throws on
/// malformed input; a font we cannot understand degrades to "no layout data",
/// which the shaper handles by falling back to plain `cmap` mapping.
library;

import 'dart:typed_data';

import 'package:bangla_pdf/src/ot/ot_reader.dart';

/// Glyph classes from `GDEF`.
class GlyphClass {
  static const int unclassified = 0;
  static const int base = 1;
  static const int ligature = 2;
  static const int mark = 3;
  static const int component = 4;
}

/// A `GSUB`/`GPOS` layout table: script/language/feature/lookup resolution.
class LayoutTable {
  LayoutTable._(this.d, this.tableOffset, this._scriptList, this._featureList,
      this._lookupList);

  /// Parses the layout table at [tableOffset]; returns `null` when absent.
  static LayoutTable? parse(OtData d, int? tableOffset) {
    if (tableOffset == null || !d.has(tableOffset, 10)) return null;
    final major = d.u16(tableOffset);
    if (major != 1) return null;
    return LayoutTable._(
      d,
      tableOffset,
      tableOffset + d.u16(tableOffset + 4),
      tableOffset + d.u16(tableOffset + 6),
      tableOffset + d.u16(tableOffset + 8),
    );
  }

  final OtData d;
  final int tableOffset;
  final int _scriptList;
  final int _featureList;
  final int _lookupList;

  /// Number of lookups in the table's LookupList.
  int get lookupCount => d.u16(_lookupList);

  /// Whether the table declares [tag] in its ScriptList.
  ///
  /// Used to tell an OpenType Indic v2 font (`bng2`) from a v1 one (`beng`);
  /// the two order their `half`/`blwf`/`pstf` rules differently.
  bool hasScript(String tag) {
    final count = d.u16(_scriptList);
    for (var i = 0; i < count; i++) {
      if (d.tag(_scriptList + 2 + 6 * i) == tag) return true;
    }
    return false;
  }

  /// Byte offset of lookup [index], or `null` when out of range.
  int? lookupOffset(int index) {
    if (index < 0 || index >= lookupCount) return null;
    return _lookupList + d.u16(_lookupList + 2 + 2 * index);
  }

  /// Offset of the LangSys record for [scriptTags] (first match wins), falling
  /// back to `DFLT`. Returns `null` when the script is absent.
  int? _langSys(List<String> scriptTags) {
    final count = d.u16(_scriptList);
    for (final want in [...scriptTags, 'DFLT']) {
      for (var i = 0; i < count; i++) {
        final rec = _scriptList + 2 + 6 * i;
        if (d.tag(rec) != want) continue;
        final script = _scriptList + d.u16(rec + 4);
        // We only use the default language system: Bengali fonts do not put
        // Bangla behaviour behind a language tag.
        final defaultLangSys = d.u16(script);
        if (defaultLangSys != 0) return script + defaultLangSys;
      }
    }
    return null;
  }

  /// Feature tag -> ordered lookup indices, for the given scripts.
  ///
  /// Only features reachable from the script's default LangSys are returned,
  /// which is what a shaper is allowed to apply.
  Map<String, List<int>> featureLookups(List<String> scriptTags) {
    final result = <String, List<int>>{};
    final langSys = _langSys(scriptTags);
    final featureCount = d.u16(_featureList);

    void addFeature(int featureIndex) {
      if (featureIndex < 0 || featureIndex >= featureCount) return;
      final rec = _featureList + 2 + 6 * featureIndex;
      final tag = d.tag(rec);
      final table = _featureList + d.u16(rec + 4);
      final n = d.u16(table + 2);
      final list = result.putIfAbsent(tag, () => <int>[]);
      for (var i = 0; i < n; i++) {
        final lookupIndex = d.u16(table + 4 + 2 * i);
        if (!list.contains(lookupIndex)) list.add(lookupIndex);
      }
    }

    if (langSys == null) {
      // No script record at all: expose every feature so a font with an
      // unusual script list still shapes rather than rendering unshaped.
      for (var i = 0; i < featureCount; i++) {
        addFeature(i);
      }
    } else {
      final required = d.u16(langSys + 2);
      if (required != 0xFFFF) addFeature(required);
      final n = d.u16(langSys + 4);
      for (var i = 0; i < n; i++) {
        addFeature(d.u16(langSys + 6 + 2 * i));
      }
    }

    for (final list in result.values) {
      list.sort();
    }
    return result;
  }
}

/// A parsed font, sufficient for shaping and for PDF embedding.
class OtFont {
  OtFont._(this.bytes, this.d, this._tables);

  /// Parses [bytes]. Returns `null` if this is not a usable sfnt font.
  static OtFont? parse(ByteData bytes) {
    final d = OtData(bytes);
    if (!d.has(0, 12)) return null;
    var base = 0;
    if (d.tag(0) == 'ttcf') {
      // TrueType collection: use the first face.
      if (!d.has(12, 4)) return null;
      base = d.u32(12);
      if (!d.has(base, 12)) return null;
    }
    final sfnt = d.u32(base);
    // 0x00010000 = TrueType outlines, 'OTTO' = CFF outlines, 'true'/'typ1' = Mac.
    if (sfnt != 0x00010000 &&
        sfnt != 0x4F54544F &&
        sfnt != 0x74727565 &&
        sfnt != 0x74797031) {
      return null;
    }
    final numTables = d.u16(base + 4);
    final tables = <String, int>{};
    final lengths = <String, int>{};
    for (var i = 0; i < numTables; i++) {
      final rec = base + 12 + 16 * i;
      if (!d.has(rec, 16)) break;
      final tag = d.tag(rec);
      tables[tag] = d.u32(rec + 8);
      lengths[tag] = d.u32(rec + 12);
    }
    if (!tables.containsKey('cmap')) return null;
    final font = OtFont._(bytes, d, tables).._tableLengths.addAll(lengths);
    font._init();
    return font;
  }

  final ByteData bytes;
  final OtData d;
  final Map<String, int> _tables;
  final Map<String, int> _tableLengths = <String, int>{};

  /// Byte offset of [tag], or `null` when the table is absent.
  int? tableOffset(String tag) => _tables[tag];

  /// Byte length of [tag], or `null` when the table is absent.
  int? tableLength(String tag) => _tableLengths[tag];

  late final int unitsPerEm = () {
    final head = _tables['head'];
    if (head == null) return 1000;
    final v = d.u16(head + 18);
    return v == 0 ? 1000 : v;
  }();

  late final int numGlyphs = () {
    final maxp = _tables['maxp'];
    return maxp == null ? 0 : d.u16(maxp + 4);
  }();

  /// Typographic ascender in font units.
  late final int ascender = () {
    final os2 = _tables['OS/2'];
    if (os2 != null && d.u16(os2) >= 2 && d.has(os2 + 70, 2)) {
      final typoAscender = d.i16(os2 + 68);
      if (typoAscender != 0) return typoAscender;
    }
    final hhea = _tables['hhea'];
    return hhea == null ? (unitsPerEm * 0.8).round() : d.i16(hhea + 4);
  }();

  /// Typographic descender in font units (negative).
  late final int descender = () {
    final os2 = _tables['OS/2'];
    if (os2 != null && d.u16(os2) >= 2 && d.has(os2 + 72, 2)) {
      final typoDescender = d.i16(os2 + 70);
      if (typoDescender != 0) return typoDescender;
    }
    final hhea = _tables['hhea'];
    return hhea == null ? -(unitsPerEm * 0.2).round() : d.i16(hhea + 6);
  }();

  /// Font bounding box in font units, from `head`.
  late final (int, int, int, int) boundingBox = () {
    final head = _tables['head'];
    if (head == null) {
      return (0, -(unitsPerEm ~/ 4), unitsPerEm, unitsPerEm);
    }
    return (
      d.i16(head + 36),
      d.i16(head + 38),
      d.i16(head + 40),
      d.i16(head + 42),
    );
  }();

  /// Byte offsets into `glyf` for each glyph, from `loca`.
  ///
  /// Null when the font has no TrueType outlines — a CFF font, for one — in
  /// which case per-glyph extents are not available and callers fall back to
  /// the font-wide ascent and descent.
  late final List<int>? _loca = () {
    final loca = _tables['loca'];
    final head = _tables['head'];
    final maxp = _tables['maxp'];
    if (loca == null || head == null || maxp == null) return null;
    if (_tables['glyf'] == null) return null;
    final long = d.i16(head + 50) != 0;
    final count = d.u16(maxp + 4) + 1;
    final out = List<int>.filled(count, 0);
    for (var i = 0; i < count; i++) {
      if (long) {
        if (!d.has(loca + i * 4, 4)) return null;
        out[i] = d.u32(loca + i * 4);
      } else {
        if (!d.has(loca + i * 2, 2)) return null;
        out[i] = d.u16(loca + i * 2) * 2;
      }
    }
    return out;
  }();

  /// Vertical ink extents of [gid] in font units, as `(yMin, yMax)`.
  ///
  /// Returns `null` for an empty glyph such as a space, or when the font has
  /// no `glyf` outlines to measure.
  (int, int)? glyphExtents(int gid) {
    final loca = _loca;
    final glyf = _tables['glyf'];
    if (loca == null || glyf == null) return null;
    if (gid < 0 || gid + 1 >= loca.length) return null;
    final start = loca[gid];
    if (loca[gid + 1] <= start) return null; // no outline
    final at = glyf + start;
    if (!d.has(at, 10)) return null;
    return (d.i16(at + 4), d.i16(at + 8));
  }

  /// PostScript name from the `name` table, sanitised for use in a PDF.
  late final String postScriptName = () {
    final name = _tables['name'];
    if (name == null) return 'BanglaFont';
    final count = d.u16(name + 2);
    final storage = name + d.u16(name + 4);
    String? best;
    for (var i = 0; i < count; i++) {
      final rec = name + 6 + 12 * i;
      final platform = d.u16(rec);
      final nameId = d.u16(rec + 6);
      if (nameId != 6) continue;
      final length = d.u16(rec + 8);
      final offset = storage + d.u16(rec + 10);
      final bytes = <int>[];
      if (platform == 3) {
        for (var k = 0; k + 1 < length; k += 2) {
          bytes.add(d.u16(offset + k));
        }
      } else {
        for (var k = 0; k < length; k++) {
          bytes.add(d.u8(offset + k));
        }
      }
      final text = String.fromCharCodes(bytes);
      best ??= text;
      if (platform == 3) break;
    }
    final raw = best ?? 'BanglaFont';
    final clean = raw.replaceAll(RegExp('[^A-Za-z0-9_-]'), '');
    return clean.isEmpty ? 'BanglaFont' : clean;
  }();

  /// Unicode scalar -> glyph id, built from the best available `cmap` subtable.
  final Map<int, int> cmap = <int, int>{};

  List<int> _advances = const <int>[];
  int _numHMetrics = 0;

  ClassDef? _gdefClasses;
  ClassDef? _markAttachClasses;
  int _markGlyphSetsOffset = 0;
  final Map<int, Coverage?> _markGlyphSetCache = <int, Coverage?>{};

  /// The font's `GSUB` table, or `null`.
  LayoutTable? gsub;

  /// The font's `GPOS` table, or `null`.
  LayoutTable? gpos;

  void _init() {
    _parseCmap();
    _parseHmtx();
    final gdef = _tables['GDEF'];
    if (gdef != null && d.has(gdef, 12)) {
      final classOffset = d.u16(gdef + 4);
      if (classOffset != 0) {
        _gdefClasses = ClassDef.parse(d, gdef + classOffset);
      }
      final markAttachOffset = d.u16(gdef + 10);
      if (markAttachOffset != 0) {
        _markAttachClasses = ClassDef.parse(d, gdef + markAttachOffset);
      }
      // Mark glyph sets arrived in GDEF 1.2.
      if (d.u32(gdef) >= 0x00010002 && d.has(gdef + 12, 2)) {
        final offset = d.u16(gdef + 12);
        if (offset != 0) _markGlyphSetsOffset = gdef + offset;
      }
    }
    gsub = LayoutTable.parse(d, _tables['GSUB']);
    gpos = LayoutTable.parse(d, _tables['GPOS']);
  }

  /// `GDEF` glyph class, or [GlyphClass.unclassified] when there is no `GDEF`.
  int glyphClass(int glyph) =>
      _gdefClasses?.of(glyph) ?? GlyphClass.unclassified;

  /// Whether [glyph] is a mark according to `GDEF`.
  bool isMark(int glyph) => glyphClass(glyph) == GlyphClass.mark;

  /// `GDEF` mark attachment class of [glyph]; 0 when unclassified.
  int markAttachClass(int glyph) => _markAttachClasses?.of(glyph) ?? 0;

  /// Coverage of mark glyph set [index] from `GDEF`, or `null` when absent.
  ///
  /// Lookups with the `useMarkFilteringSet` flag match only the marks in their
  /// set and step over every other mark.
  Coverage? markGlyphSet(int index) {
    if (_markGlyphSetsOffset == 0) return null;
    return _markGlyphSetCache.putIfAbsent(index, () {
      final base = _markGlyphSetsOffset;
      if (d.u16(base) != 1) return null;
      if (index < 0 || index >= d.u16(base + 2)) return null;
      final offset = d.u32(base + 4 + 4 * index);
      if (offset == 0) return null;
      return Coverage.parse(d, base + offset);
    });
  }

  /// Horizontal advance of [glyph] in font units.
  int advance(int glyph) {
    if (_advances.isEmpty) return (unitsPerEm * 0.5).round();
    if (glyph < _advances.length) return _advances[glyph];
    return _advances[_numHMetrics - 1];
  }

  /// Glyph id for [rune], or `null` when the font has no glyph for it.
  int? glyphForRune(int rune) => cmap[rune];

  /// Whether the font covers the Bengali block beyond a token codepoint or two.
  ///
  /// Used to decide whether a user-supplied font is a real Unicode Bangla font
  /// or a legacy 8-bit ANSI font, which is what 1.x shipped.
  late final bool hasBengaliCoverage = () {
    // The 11 most common Bangla letters. A Unicode Bangla font has all of them;
    // an ANSI font has none.
    const probes = <int>[
      0x0995, 0x0996, 0x0997, 0x099A, 0x09A4, 0x09A6, 0x09A8, //
      0x09AC, 0x09AE, 0x09B0, 0x09B8,
    ];
    var hits = 0;
    for (final p in probes) {
      if (cmap.containsKey(p)) hits++;
    }
    return hits >= probes.length - 1;
  }();

  void _parseHmtx() {
    final hhea = _tables['hhea'];
    final hmtx = _tables['hmtx'];
    if (hhea == null || hmtx == null) return;
    _numHMetrics = d.u16(hhea + 34);
    if (_numHMetrics == 0) return;
    final out = List<int>.filled(
      numGlyphs > 0 ? numGlyphs : _numHMetrics,
      0,
    );
    var last = 0;
    for (var i = 0; i < out.length; i++) {
      if (i < _numHMetrics) {
        last = d.u16(hmtx + 4 * i);
      }
      out[i] = last;
    }
    _advances = out;
  }

  void _parseCmap() {
    final cmapOffset = _tables['cmap'];
    if (cmapOffset == null) return;
    final numSubtables = d.u16(cmapOffset + 2);

    // Preference order: (3,10) UCS-4, (3,1) BMP, (0,*) Unicode, (3,0) symbol,
    // (1,0) Mac Roman. The last two are how legacy ANSI Bangla fonts encode.
    int rank(int platform, int encoding) {
      if (platform == 3 && encoding == 10) return 0;
      if (platform == 3 && encoding == 1) return 1;
      if (platform == 0) return 2;
      if (platform == 3 && encoding == 0) return 3;
      if (platform == 1 && encoding == 0) return 4;
      return 5;
    }

    var bestRank = 99;
    var bestOffset = -1;
    var bestSymbol = false;
    for (var i = 0; i < numSubtables; i++) {
      final rec = cmapOffset + 4 + 8 * i;
      final platform = d.u16(rec);
      final encoding = d.u16(rec + 2);
      final sub = cmapOffset + d.u32(rec + 4);
      final r = rank(platform, encoding);
      if (r < bestRank) {
        bestRank = r;
        bestOffset = sub;
        bestSymbol = platform == 3 && encoding == 0;
      }
    }
    if (bestOffset < 0) return;
    _parseCmapSubtable(bestOffset, symbol: bestSymbol);
  }

  void _parseCmapSubtable(int sub, {required bool symbol}) {
    switch (d.u16(sub)) {
      case 0:
        for (var c = 0; c < 256; c++) {
          final g = d.u8(sub + 6 + c);
          if (g != 0) cmap[c] = g;
        }
      case 4:
        final segX2 = d.u16(sub + 6);
        final segs = segX2 ~/ 2;
        final endO = sub + 14;
        final startO = endO + segX2 + 2;
        final deltaO = startO + segX2;
        final rangeO = deltaO + segX2;
        for (var s = 0; s < segs; s++) {
          final end = d.u16(endO + 2 * s);
          final start = d.u16(startO + 2 * s);
          final delta = d.u16(deltaO + 2 * s);
          final rangeOffset = d.u16(rangeO + 2 * s);
          if (start == 0xFFFF) continue;
          for (var c = start; c <= end && c != 0x10000; c++) {
            int g;
            if (rangeOffset == 0) {
              g = (c + delta) & 0xFFFF;
            } else {
              final gi = rangeO + 2 * s + rangeOffset + 2 * (c - start);
              g = d.u16(gi);
              if (g != 0) g = (g + delta) & 0xFFFF;
            }
            if (g == 0) continue;
            cmap[c] = g;
            // Symbol subtables map into the F0xx private-use range; also expose
            // the low byte so plain Latin-1 lookups succeed.
            if (symbol && c >= 0xF000 && c <= 0xF0FF) {
              cmap.putIfAbsent(c & 0xFF, () => g);
            }
          }
        }
      case 6:
        final first = d.u16(sub + 6);
        final count = d.u16(sub + 8);
        for (var i = 0; i < count; i++) {
          final g = d.u16(sub + 10 + 2 * i);
          if (g != 0) cmap[first + i] = g;
        }
      case 12:
        final nGroups = d.u32(sub + 12);
        for (var i = 0; i < nGroups; i++) {
          final o = sub + 16 + 12 * i;
          final start = d.u32(o);
          final end = d.u32(o + 4);
          final startGlyph = d.u32(o + 8);
          if (end < start || end - start > 0x10FFFF) continue;
          for (var c = start; c <= end; c++) {
            cmap[c] = startGlyph + (c - start);
          }
        }
      default:
        break;
    }
  }
}
