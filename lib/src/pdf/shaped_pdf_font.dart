/// A PDF Type0 font addressed by **glyph id** rather than by character.
///
/// `package:pdf`'s own [PdfTtfFont] allocates one CID per Unicode rune and
/// picks the glyph through the font's `cmap`. That cannot express a shaped
/// run: a conjunct such as ক্ষ্ম is a single glyph with no `cmap` entry, and a
/// pre-base matra has to be emitted before the consonant it follows.
///
/// This font instead allocates a CID per *(glyph, source text)* pair and
/// writes an explicit `/CIDToGIDMap`, so:
///
///  * any glyph in the font can be drawn, including ligatures and positional
///    variants that no codepoint maps to;
///  * the `/ToUnicode` CMap can map one CID to a *multi-character* string, so
///    copying ক্ষ্ম out of the PDF yields all five original codepoints;
///  * the glyphs of a cluster can be emitted in visual order while the whole
///    cluster's text is attached to the first of them, so both stream-order
///    and position-order text extractors recover the logical Unicode.
///
/// ## Why this file imports `package:pdf/src/...`
///
/// `package:pdf` exports `PdfFont` but not the object and format primitives
/// (`PdfDict`, `PdfStream`, `PdfObjectStream`, ...) needed to subclass it.
/// Writing a correct CID font is impossible without them. The dependency is
/// confined to this one file and pinned to `pdf: ^3.11.0`; the round-trip
/// tests fail loudly if the internals move.
library;

// ignore_for_file: implementation_imports

import 'dart:typed_data';

import 'package:bangla_pdf/src/ot/ot_font.dart';
import 'package:pdf/pdf.dart' show PdfFont, PdfFontMetrics, PdfName;
import 'package:pdf/src/pdf/document.dart';
import 'package:pdf/src/pdf/format/array.dart';
import 'package:pdf/src/pdf/format/base.dart';
import 'package:pdf/src/pdf/format/dict.dart';
import 'package:pdf/src/pdf/format/num.dart';
import 'package:pdf/src/pdf/format/stream.dart';
import 'package:pdf/src/pdf/format/string.dart';
import 'package:pdf/src/pdf/obj/object.dart';
import 'package:pdf/src/pdf/obj/object_stream.dart';

/// Sentinel code unit introducing a two-unit signed TJ adjustment inside an
/// encoded glyph string. CIDs are never allocated this high.
const int _kAdjust = 0xFFFF;

/// Sentinel introducing a marked-content control token.
const int _kControl = 0xFFFE;

/// Highest CID this font will allocate, leaving the sentinels free.
const int _kMaxCid = 0xFFFD;

/// Control opcodes carried after [_kControl].
const int _kOpBeginSpan = 1;
const int _kOpEndSpan = 2;

/// A Type0/Identity-H CID font built from shaped glyph runs.
class ShapedPdfFont extends PdfFont {
  /// Creates the font in [document], embedding [otf].
  ShapedPdfFont.create(PdfDocument document, this.otf)
      : super.create(document, subtype: '/Type0') {
    _file = PdfObjectStream(document, isBinary: true);
    _toUnicode = _ToUnicodeCmap(document, this);
    _cidToGid = _CidToGidMap(document, this);
    _descriptor = _Descriptor(document, this, _file);
    _widths = PdfObject<PdfArray>(document, params: PdfArray());
  }

  /// The parsed font this PDF font embeds.
  final OtFont otf;

  late final PdfObjectStream _file;
  late final _ToUnicodeCmap _toUnicode;
  late final _CidToGidMap _cidToGid;
  late final _Descriptor _descriptor;
  late final PdfObject<PdfArray> _widths;

  /// CID 0 is `.notdef` and must stay unused.
  final List<int> _gidForCid = <int>[0];
  final List<String> _textForCid = <String>[''];
  final List<int> _advanceForCid = <int>[0];
  final Map<int, List<int>> _cidsByKey = <int, List<int>>{};

  @override
  String get fontName => otf.postScriptName;

  @override
  double get ascent => otf.ascender / otf.unitsPerEm;

  @override
  double get descent => otf.descender / otf.unitsPerEm;

  @override
  int get unitsPerEm => otf.unitsPerEm;

  /// Number of CIDs allocated so far, including `.notdef`.
  int get cidCount => _gidForCid.length;

  /// GID drawn for [cid].
  int gidForCid(int cid) =>
      (cid >= 0 && cid < _gidForCid.length) ? _gidForCid[cid] : 0;

  /// Source text [cid] maps back to; empty when the CID carries no text.
  String textForCid(int cid) =>
      (cid >= 0 && cid < _textForCid.length) ? _textForCid[cid] : '';

  /// Advance recorded for [cid], in font units.
  int advanceForCid(int cid) =>
      (cid >= 0 && cid < _advanceForCid.length) ? _advanceForCid[cid] : 0;

  /// Allocates (or reuses) a CID drawing [gid], extracting as [text], and
  /// advancing by [advance] font units.
  ///
  /// All three are part of the identity. Two CIDs share a GID when the same
  /// glyph carries different text — which is how the first glyph of a cluster
  /// owns the cluster's whole text while the rest own none. They also differ
  /// when GPOS gave the glyph a different advance, so the real advance can go
  /// into `/W` and the content stream needs no correcting kerns; without that,
  /// text extractors read the corrections as word gaps and insert spaces.
  int cidFor(int gid, String text, int advance) {
    final key = Object.hash(gid, text, advance);
    for (final candidate in _cidsByKey[key] ?? const <int>[]) {
      if (_gidForCid[candidate] == gid &&
          _textForCid[candidate] == text &&
          _advanceForCid[candidate] == advance) {
        return candidate;
      }
    }
    if (_gidForCid.length > _kMaxCid) return 0;
    final cid = _gidForCid.length;
    _gidForCid.add(gid);
    _textForCid.add(text);
    _advanceForCid.add(advance);
    _cidsByKey.putIfAbsent(key, () => <int>[]).add(cid);
    return cid;
  }

  /// Builds the opaque string consumed by [putText].
  ///
  /// [cids] are CIDs from [cidFor]; [adjustments] holds the TJ adjustment (in
  /// thousandths of an em, positive meaning "move left") to apply *before* the
  /// CID at the same index.
  static String encode(List<int> cids, List<int> adjustments) {
    assert(cids.length == adjustments.length);
    final units = <int>[];
    for (var i = 0; i < cids.length; i++) {
      final adjust = adjustments[i];
      if (adjust != 0) {
        final raw = adjust & 0xFFFFFFFF;
        units
          ..add(_kAdjust)
          ..add((raw >> 16) & 0xFFFF)
          ..add(raw & 0xFFFF);
      }
      units.add(cids[i]);
    }
    return String.fromCharCodes(units);
  }

  /// Encodes a `/Span <</ActualText ...>> BDC` marker.
  ///
  /// Bengali reorders glyphs, so glyph order is not text order and no
  /// per-glyph `/ToUnicode` mapping can express the logical string. PDF's
  /// answer is `/ActualText` on a marked-content span, which every mainstream
  /// viewer and `pdftotext` honour in preference to the glyphs' own text.
  static String beginSpan(String actualText) {
    final units = <int>[_kControl, _kOpBeginSpan, actualText.length];
    units.addAll(actualText.codeUnits);
    return String.fromCharCodes(units);
  }

  /// Encodes the matching `EMC`.
  static String endSpan() =>
      String.fromCharCodes(<int>[_kControl, _kOpEndSpan, 0]);

  @override
  void putText(PdfStream stream, String text) {
    final units = text.codeUnits;
    var open = false;
    void closeHex() {
      if (open) {
        stream.putByte(0x3e); // '>'
        open = false;
      }
    }

    // `drawString` has already written `BT ... Td [`, and will write `]TJ ET`
    // after us. A control token therefore closes that array and text object,
    // emits its marked-content operator, and reopens an empty one so the
    // caller's trailing `]TJ ET` still balances.
    void reopen() => stream.putString(' BT $name 1 Tf 0 0 Td [');

    for (var i = 0; i < units.length; i++) {
      final unit = units[i];

      if (unit == _kControl && i + 2 < units.length) {
        final op = units[i + 1];
        final length = units[i + 2];
        closeHex();
        stream.putString(']TJ ET ');
        if (op == _kOpBeginSpan) {
          final buffer = StringBuffer('FEFF');
          for (var k = 0; k < length && i + 3 + k < units.length; k++) {
            buffer.write(
              units[i + 3 + k].toRadixString(16).toUpperCase().padLeft(4, '0'),
            );
          }
          stream.putString('/Span <</ActualText <$buffer>>> BDC');
        } else {
          stream.putString('EMC');
        }
        reopen();
        i += 2 + length;
        continue;
      }

      if (unit == _kAdjust && i + 2 < units.length) {
        final raw = (units[i + 1] << 16) | units[i + 2];
        final value = raw >= 0x80000000 ? raw - 0x100000000 : raw;
        i += 2;
        closeHex();
        stream.putString(' $value ');
        continue;
      }

      if (!open) {
        stream.putByte(0x3c); // '<'
        open = true;
      }
      stream.putString(unit.toRadixString(16).toUpperCase().padLeft(4, '0'));
    }
    closeHex();
  }

  @override
  PdfFontMetrics glyphMetrics(int charCode) {
    final width = advanceForCid(charCode) / otf.unitsPerEm;
    return PdfFontMetrics(
      left: 0,
      top: descent,
      right: width,
      bottom: ascent,
      advanceWidth: width,
    );
  }

  @override
  PdfFontMetrics stringMetrics(String s, {double letterSpacing = 0}) {
    if (s.isEmpty) return PdfFontMetrics.zero;
    var width = 0.0;
    final units = s.codeUnits;
    for (var i = 0; i < units.length; i++) {
      if (units[i] == _kControl && i + 2 < units.length) {
        i += 2 + units[i + 2];
        continue;
      }
      if (units[i] == _kAdjust && i + 2 < units.length) {
        final raw = (units[i + 1] << 16) | units[i + 2];
        final value = raw >= 0x80000000 ? raw - 0x100000000 : raw;
        width -= value / 1000.0;
        i += 2;
        continue;
      }
      width += advanceForCid(units[i]) / otf.unitsPerEm;
    }
    return PdfFontMetrics(
      left: 0,
      top: descent,
      right: width,
      bottom: ascent,
      advanceWidth: width,
    );
  }

  @override
  bool isRuneSupported(int charCode) => otf.cmap.containsKey(charCode);

  @override
  void prepare() {
    super.prepare();

    _file.buf.putBytes(otf.bytes.buffer.asUint8List(
      otf.bytes.offsetInBytes,
      otf.bytes.lengthInBytes,
    ));
    _file.params['/Length1'] = PdfNum(otf.bytes.lengthInBytes);

    for (var cid = 0; cid < _gidForCid.length; cid++) {
      _widths.params.add(
        PdfNum((_advanceForCid[cid] * 1000 / otf.unitsPerEm).round()),
      );
    }

    final descendant = PdfDict.values(<String, PdfDataType>{
      '/Type': const PdfName('/Font'),
      '/Subtype': const PdfName('/CIDFontType2'),
      '/BaseFont': PdfName('/$fontName'),
      '/CIDSystemInfo': PdfDict.values(<String, PdfDataType>{
        '/Registry': PdfString.fromString('Adobe'),
        '/Ordering': PdfString.fromString('Identity'),
        '/Supplement': const PdfNum(0),
      }),
      '/FontDescriptor': _descriptor.ref(),
      '/DW': const PdfNum(1000),
      '/W': PdfArray(<PdfDataType>[const PdfNum(0), _widths.ref()]),
      '/CIDToGIDMap': _cidToGid.ref(),
    });

    params['/BaseFont'] = PdfName('/$fontName');
    params['/Encoding'] = const PdfName('/Identity-H');
    params['/DescendantFonts'] = PdfArray(<PdfDataType>[descendant]);
    params['/ToUnicode'] = _toUnicode.ref();
  }
}

/// `/FontDescriptor` for a [ShapedPdfFont].
class _Descriptor extends PdfObject<PdfDict> {
  _Descriptor(super.document, this.font, this.file)
      : super(
          params: PdfDict.values(<String, PdfDataType>{
            '/Type': const PdfName('/FontDescriptor'),
          }),
        );

  final ShapedPdfFont font;
  final PdfObjectStream file;

  @override
  void prepare() {
    super.prepare();
    final upem = font.otf.unitsPerEm;
    final (xMin, yMin, xMax, yMax) = font.otf.boundingBox;
    int scaled(int v) => (v * 1000 / upem).round();

    params['/FontName'] = PdfName('/${font.fontName}');
    params['/FontFile2'] = file.ref();
    // Symbolic: the font's own encoding governs, which is what Identity-H
    // requires for a script outside the standard Latin sets.
    params['/Flags'] = const PdfNum(4);
    params['/FontBBox'] = PdfArray.fromNum(<int>[
      scaled(xMin),
      scaled(yMin),
      scaled(xMax),
      scaled(yMax),
    ]);
    params['/Ascent'] = PdfNum(scaled(font.otf.ascender));
    params['/Descent'] = PdfNum(scaled(font.otf.descender));
    params['/ItalicAngle'] = const PdfNum(0);
    params['/CapHeight'] = PdfNum(scaled(font.otf.ascender));
    params['/StemV'] = const PdfNum(80);
  }
}

/// The `/CIDToGIDMap` stream: two big-endian bytes of GID per CID.
class _CidToGidMap extends PdfObjectStream {
  _CidToGidMap(super.document, this.font) : super(isBinary: true);

  final ShapedPdfFont font;

  @override
  void prepare() {
    final bytes = Uint8List(font.cidCount * 2);
    for (var cid = 0; cid < font.cidCount; cid++) {
      final gid = font.gidForCid(cid);
      bytes[cid * 2] = (gid >> 8) & 0xFF;
      bytes[cid * 2 + 1] = gid & 0xFF;
    }
    buf.putBytes(bytes);
    super.prepare();
  }
}

/// The `/ToUnicode` CMap. Unlike `package:pdf`'s, a CID may map to a string of
/// several codepoints, which is what makes conjuncts copy out correctly.
class _ToUnicodeCmap extends PdfObjectStream {
  _ToUnicodeCmap(super.document, this.font);

  final ShapedPdfFont font;

  static String _utf16beHex(String text) {
    final buffer = StringBuffer();
    for (final unit in text.codeUnits) {
      buffer.write(unit.toRadixString(16).toUpperCase().padLeft(4, '0'));
    }
    return buffer.toString();
  }

  @override
  void prepare() {
    final entries = <String>[];
    for (var cid = 1; cid < font.cidCount; cid++) {
      final text = font.textForCid(cid);
      // A CID with no text is a continuation glyph of a cluster whose text is
      // already carried by an earlier CID. Mapping it to an empty destination
      // is what tells an extractor to emit nothing for it.
      entries.add(
        '<${cid.toRadixString(16).toUpperCase().padLeft(4, '0')}> '
        '<${_utf16beHex(text)}>',
      );
    }

    buf.putString(
      '/CIDInit /ProcSet findresource begin\n'
      '12 dict begin\n'
      'begincmap\n'
      '/CIDSystemInfo <<\n'
      '  /Registry (Adobe)\n'
      '  /Ordering (UCS)\n'
      '  /Supplement 0\n'
      '>> def\n'
      '/CMapName /Adobe-Identity-UCS def\n'
      '/CMapType 2 def\n'
      '1 begincodespacerange\n'
      '<0000> <FFFF>\n'
      'endcodespacerange\n',
    );

    // beginbfchar allows at most 100 entries per block.
    for (var i = 0; i < entries.length; i += 100) {
      final chunk = entries.skip(i).take(100).toList();
      buf.putString('${chunk.length} beginbfchar\n');
      for (final entry in chunk) {
        buf.putString('$entry\n');
      }
      buf.putString('endbfchar\n');
    }

    buf.putString(
      'endcmap\n'
      'CMapName currentdict /CMap defineresource pop\n'
      'end\n'
      'end',
    );
    super.prepare();
  }
}
