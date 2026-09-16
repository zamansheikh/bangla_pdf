/// What extraction needs to know about a font referenced by a page.
///
/// Chiefly: how wide a character code is, and what Unicode it maps to. A PDF
/// can say so directly with a `/ToUnicode` CMap, or leave it to be inferred
/// from the encoding — or, in a Bijoy document, say something that is simply
/// wrong, which is why [isBijoy] exists.
library;

import 'dart:typed_data';

import 'package:bangla_pdf/src/extract/bijoy.dart';
import 'package:bangla_pdf/src/extract/glyph_reverse.dart';
import 'package:bangla_pdf/src/extract/pdf_lexer.dart';
import 'package:bangla_pdf/src/extract/pdf_object.dart';
import 'package:bangla_pdf/src/extract/pdf_reader.dart';
import 'package:bangla_pdf/src/ot/ot_font.dart';

/// A font as seen from the text-extraction side.
class FontInfo {
  FontInfo._({
    required this.baseFont,
    required this.subtype,
    required this.twoByte,
    required this.toUnicode,
    required this.differences,
    required this.embedded,
    required this.cidToGid,
  });

  /// Reads the font dictionary [dict].
  factory FontInfo.parse(PdfReader reader, PdfDictObj dict) {
    // ignore: prefer_final_locals
    var cidToGid = <int, int>{};
    final subtypeObj = reader.resolve(dict['Subtype']);
    final subtype = subtypeObj is PdfNameObj ? subtypeObj.value : '';
    final baseObj = reader.resolve(dict['BaseFont']);
    var baseFont = baseObj is PdfNameObj ? baseObj.value : '';
    // Subset fonts are named "ABCDEF+RealName".
    if (baseFont.length > 7 && baseFont[6] == '+') {
      baseFont = baseFont.substring(7);
    }

    var descendant = dict;
    if (subtype == 'Type0') {
      final list = reader.resolve(dict['DescendantFonts']);
      if (list is PdfArrayObj && list.length > 0) {
        final d = reader.resolve(list[0]);
        if (d is PdfDictObj) descendant = d;
      }
    }

    // A Type0 font with Identity encoding uses two-byte codes. Other CMaps
    // exist but are vanishingly rare in Bangla documents.
    var twoByte = false;
    if (subtype == 'Type0') {
      twoByte = true;
      final enc = reader.resolve(dict['Encoding']);
      if (enc is PdfNameObj && enc.value.contains('OneByte')) twoByte = false;
    }

    final toUnicode = <int, String>{};
    var declaredTwoByte = twoByte;
    final cmapObj = reader.resolve(dict['ToUnicode']);
    if (cmapObj is PdfStreamObj) {
      final data = reader.decoded(cmapObj);
      if (data != null) {
        declaredTwoByte = _parseToUnicode(data, toUnicode) || twoByte;
      }
    }

    final differences = <int, String>{};
    final enc = reader.resolve(dict['Encoding']);
    if (enc is PdfDictObj) {
      final diff = reader.resolve(enc['Differences']);
      if (diff is PdfArrayObj) {
        var code = 0;
        for (final item in diff.values) {
          final v = reader.resolve(item);
          if (v is PdfNumObj) {
            code = v.asInt;
          } else if (v is PdfNameObj) {
            differences[code++] = v.value;
          }
        }
      }
    }

    OtFont? embedded;
    final descriptor = reader.resolve(descendant['FontDescriptor']);
    if (descriptor is PdfDictObj) {
      for (final key in const <String>['FontFile2', 'FontFile3', 'FontFile']) {
        final file = reader.resolve(descriptor[key]);
        if (file is PdfStreamObj) {
          final data = reader.decoded(file);
          if (data != null && data.isNotEmpty) {
            embedded = OtFont.parse(ByteData.sublistView(data));
            if (embedded != null) break;
          }
        }
      }
    }

    // A CID font may remap CIDs onto glyph ids with a stream; Identity means
    // the CID is the glyph id, which is by far the common case.
    final mapObj = reader.resolve(descendant['CIDToGIDMap']);
    if (mapObj is PdfStreamObj) {
      final data = reader.decoded(mapObj);
      if (data != null) {
        for (var cid = 0; cid * 2 + 1 < data.length; cid++) {
          final gid = (data[cid * 2] << 8) | data[cid * 2 + 1];
          if (gid != 0) cidToGid[cid] = gid;
        }
      }
    }

    return FontInfo._(
      baseFont: baseFont,
      subtype: subtype,
      twoByte: declaredTwoByte,
      toUnicode: toUnicode,
      differences: differences,
      embedded: embedded,
      cidToGid: cidToGid,
    );
  }

  /// PostScript name with any subset prefix stripped.
  final String baseFont;

  /// `Type0`, `TrueType`, `Type1`, ...
  final String subtype;

  /// Whether character codes in a string are two bytes wide.
  final bool twoByte;

  /// Code -> Unicode, from the `/ToUnicode` CMap.
  final Map<int, String> toUnicode;

  /// Code -> glyph name, from `/Encoding /Differences`.
  final Map<int, String> differences;

  /// The embedded font program, when one could be parsed.
  final OtFont? embedded;

  /// CID -> glyph id, from a `/CIDToGIDMap` stream. Empty means identity.
  final Map<int, int> cidToGid;

  /// Whether this font says nothing about what its codes mean.
  ///
  /// Such a font is the case un-shaping exists for: all that survives is which
  /// glyph was drawn.
  bool get hasNoTextMapping => toUnicode.isEmpty && differences.isEmpty;

  /// Whether a code in a string is a CID, and so identifies a glyph.
  bool get codesAreGlyphIds => subtype == 'Type0';

  /// Whether the `/ToUnicode` CMap disagrees with the embedded font's own
  /// `cmap` about Bengali glyphs, badly enough that it cannot be trusted.
  ///
  /// Microsoft Word writes such CMaps. It pairs glyphs with characters by
  /// position, which breaks as soon as a cluster is drawn out of typing order:
  /// `শি` is drawn `[ি, শ]` but typed `[শ, ি]`, so the CMap records ি→শ and
  /// শ→ি. Every reordered pair gets exchanged — ে with দ, র with ে, ৈ with ব —
  /// and which pairs depends on which words the document happens to contain,
  /// so no fixed correction table can undo it. The glyphs themselves are fine,
  /// and so is the font; reading them back through the font is what recovers
  /// the text.
  ///
  /// A glyph the font's `cmap` reaches directly is compared against what the
  /// CMap claims for it. An entry that includes the glyph's own character
  /// agrees — a cluster's first glyph legitimately carries the whole cluster's
  /// text — and an empty entry says nothing either way.
  late final bool toUnicodeContradictsFont = () {
    final font = embedded;
    if (font == null || toUnicode.isEmpty || isBijoy) return false;
    if (!codesAreGlyphIds) return false;

    final bengaliOfGlyph = <int, List<int>>{};
    for (final entry in font.cmap.entries) {
      if (entry.key < 0x0980 || entry.key > 0x09FF) continue;
      (bengaliOfGlyph[entry.value] ??= <int>[]).add(entry.key);
    }
    if (bengaliOfGlyph.isEmpty) return false;

    var agree = 0;
    var disagree = 0;
    for (final entry in toUnicode.entries) {
      if (entry.value.isEmpty) continue;
      final own = bengaliOfGlyph[glyphFor(entry.key)];
      if (own == null) continue;
      final claimed = _decomposeBengali(entry.value);
      final matches = own.any(
        (codepoint) => _decomposeBengali(String.fromCharCode(codepoint))
            .runes
            .every((c) => claimed.runes.contains(c)),
      );
      if (matches) {
        agree++;
      } else {
        disagree++;
      }
    }
    // One stray entry is a font with two codepoints on one glyph, or a
    // writer's rounding; a pattern of them is a CMap that was built wrong.
    return disagree >= 3 && disagree * 10 >= agree + disagree;
  }();

  /// Whether the document's own statement of what the codes mean should be
  /// ignored in favour of reading the glyphs back: there is none, or it
  /// contradicts the font it describes.
  ///
  /// Only a CID font's codes name glyphs. A simple font's code is a byte in an
  /// encoding — WinAnsi, a symbol encoding, a Bijoy table — and reading it as a
  /// glyph id turns a space into whatever glyph 32 happens to be.
  bool get textMappingUntrusted =>
      codesAreGlyphIds && (hasNoTextMapping || toUnicodeContradictsFont);

  /// The font's glyphs read backwards, built on first use.
  ///
  /// Only ever consulted when the document offers nothing trustworthy, because
  /// a reverse map is inference: it reconstructs the text most likely to have
  /// produced a glyph, which is not always the text that did.
  late final GlyphReverseMap? reverseMap = () {
    final font = embedded;
    if (font == null || !textMappingUntrusted) return null;
    final map = GlyphReverseMap.build(font);
    return map.isEmpty ? null : map;
  }();

  /// The glyph id [code] draws.
  int glyphFor(int code) => cidToGid[code] ?? code;

  /// Recovers the text of a whole run of codes by reading the glyphs back.
  ///
  /// Done per run rather than per code because Bengali draws a cluster out of
  /// order — the reordering can only be undone with the run in hand. A glyph
  /// the font cannot name — one a subsetter left in the font but pruned from
  /// its `cmap`, as Word does with `ূ` — falls back to the document's mapping
  /// for that glyph alone.
  String? unshape(List<int> codes) {
    final map = reverseMap;
    if (map == null) return null;
    final text = map.decodeRun(
      codes.map(glyphFor),
      fallback: (i) => toUnicode[codes[i]],
    );
    return text.isEmpty ? null : text;
  }

  /// Recovers the text of a collected run, which may span several show
  /// operators and contain word gaps.
  ///
  /// A negative code marks a gap written as a `TJ` adjustment rather than as a
  /// space glyph; the run is read back one word at a time between them. When
  /// the font cannot be read back at all, the document's own mapping is used,
  /// which is no worse than not collecting the run.
  String unshapeRun(List<int> codes) {
    final out = StringBuffer();
    var gap = false;
    var word = <int>[];
    void finish() {
      if (word.isEmpty) return;
      final text = unshape(word) ?? word.map((c) => unicodeFor(c) ?? '').join();
      final so = out.toString();
      // A gap beside a drawn space is the same space, widened by justification.
      if (gap &&
          so.isNotEmpty &&
          !so.endsWith(' ') &&
          !so.endsWith('\n') &&
          !text.startsWith(' ')) {
        out.write(' ');
      }
      out.write(text);
      gap = false;
      word = <int>[];
    }

    for (final code in codes) {
      if (code < 0) {
        finish();
        gap = true;
      } else {
        word.add(code);
      }
    }
    finish();
    return out.toString();
  }

  /// Whether this font renders Bangla from Bijoy/ANSI byte values.
  ///
  /// The giveaway is the embedded font itself: a Bijoy face draws Bangla but
  /// has no Bengali in its `cmap`, because it is addressed by Latin-1 byte
  /// values. Code width is no help — `package:pdf` and several other writers
  /// wrap even an 8-bit font in a Type0 CID font, so a Bijoy document can very
  /// well use two-byte codes whose `/ToUnicode` maps back to Latin-1.
  late final bool isBijoy = () {
    final font = embedded;
    if (font != null && font.hasBengaliCoverage) return false;
    // A face carrying Bengali shaping rules is a Unicode font, whatever its
    // cmap says. Word subsets a font once per encoding: the WinAnsi copy of
    // NikoshBAN it uses for digits and punctuation keeps GSUB (script `beng`)
    // but none of the Bengali cmap entries, and the name check below would
    // then call it Bijoy and turn its ASCII into noise. A Bijoy face is
    // addressed by Latin byte values and has no use for a Bengali script table.
    if (font != null && font.declaresBengaliScript) return false;
    if (looksLikeBijoyFontName(baseFont)) return true;
    if (font == null) return false;
    if (font.cmap.isEmpty) return false;

    // An embedded face with a Bangla-sounding name and no Bengali coverage is
    // the classic Bijoy setup.
    final name = baseFont.toLowerCase();
    const banglaish = <String>[
      'bangla',
      'bangali',
      'bengali',
      'lipi',
      'purush',
      'rupali',
      'nikosh',
      'sutonny',
      'tonny',
      'borno',
      'kalpurush',
    ];
    if (banglaish.any(name.contains)) return true;

    // Last resort: the font covers the Latin-1 supplement densely, which a
    // text font for English has no reason to do, and covers no Bengali.
    final high = font.cmap.keys.where((c) => c >= 0xA0 && c <= 0xFF).length;
    return high >= 60;
  }();

  /// Splits [bytes] into character codes according to this font's width.
  List<int> codes(Uint8List bytes) {
    if (!twoByte) return List<int>.of(bytes);
    final out = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      out.add((bytes[i] << 8) | bytes[i + 1]);
    }
    if (bytes.length.isOdd) out.add(bytes.last);
    return out;
  }

  /// The glyph ids [bytes] draw, for reading glyphs back.
  ///
  /// Unlike [codes], an incomplete trailing byte is dropped rather than kept:
  /// it is not a CID, so it names no glyph. Word emits exactly that — `( ) TJ`,
  /// one byte, with a two-byte CID font selected — and taking the byte as glyph
  /// 32 draws whatever glyph 32 is. In NikoshBAN that is `=`.
  List<int> glyphCodes(Uint8List bytes) {
    final out = codes(bytes);
    if (twoByte && bytes.length.isOdd && out.isNotEmpty) out.removeLast();
    return out;
  }

  /// The text [code] represents, or `null` when nothing is known.
  String? unicodeFor(int code) {
    final mapped = toUnicode[code];
    if (mapped != null && mapped.isNotEmpty) return mapped;
    if (toUnicode.containsKey(code)) return ''; // deliberately empty
    if (twoByte) return null;
    final name = differences[code];
    if (name != null) {
      final fromName = _glyphNameToUnicode(name);
      if (fromName != null) return fromName;
    }
    // A simple font with no CMap: the code is its own Latin-1 character. For a
    // Bijoy font that is exactly what we want, since the Bijoy converter reads
    // those bytes.
    if (code >= 0x20 && code < 0x100) return String.fromCharCode(code);
    return null;
  }

  static String? _glyphNameToUnicode(String name) {
    if (name.startsWith('uni') && name.length >= 7) {
      final v = int.tryParse(name.substring(3, 7), radix: 16);
      if (v != null) return String.fromCharCode(v);
    }
    if (name.startsWith('u') && name.length >= 5 && name.length <= 7) {
      final v = int.tryParse(name.substring(1), radix: 16);
      if (v != null) return String.fromCharCode(v);
    }
    return null;
  }

  /// Parses a `/ToUnicode` CMap into [out].
  ///
  /// Returns true when the CMap declares two-byte codes.
  static bool _parseToUnicode(Uint8List data, Map<int, String> out) {
    final lexer = PdfLexer(data);
    var twoByte = false;
    final pending = <PdfObj>[];

    String textOf(PdfObj o) {
      if (o is! PdfStringObj) return '';
      // Destinations are UTF-16BE.
      final b = o.bytes;
      final units = <int>[];
      for (var i = 0; i + 1 < b.length; i += 2) {
        units.add((b[i] << 8) | b[i + 1]);
      }
      if (units.isNotEmpty && units.first == 0xFEFF) units.removeAt(0);
      return String.fromCharCodes(units);
    }

    int codeOf(PdfObj o) {
      if (o is! PdfStringObj) return -1;
      var v = 0;
      for (final b in o.bytes) {
        v = (v << 8) | b;
      }
      return v;
    }

    while (true) {
      final token = lexer.next();
      if (token == null) break;
      if (token is! PdfOperatorObj) {
        pending.add(token);
        if (pending.length > 600) pending.removeRange(0, 300);
        continue;
      }
      switch (token.name) {
        case 'endcodespacerange':
          for (final o in pending) {
            if (o is PdfStringObj && o.bytes.length >= 2) twoByte = true;
          }
          pending.clear();
        case 'endbfchar':
          for (var i = 0; i + 1 < pending.length; i += 2) {
            final code = codeOf(pending[i]);
            if (code >= 0) out[code] = textOf(pending[i + 1]);
          }
          pending.clear();
        case 'endbfrange':
          for (var i = 0; i + 2 < pending.length; i += 3) {
            final lo = codeOf(pending[i]);
            final hi = codeOf(pending[i + 1]);
            final dst = pending[i + 2];
            if (lo < 0 || hi < lo || hi - lo > 0xFFFF) continue;
            if (dst is PdfArrayObj) {
              for (var k = 0; k <= hi - lo && k < dst.length; k++) {
                out[lo + k] = textOf(dst[k]);
              }
            } else if (dst is PdfStringObj) {
              final base = textOf(dst);
              if (base.isEmpty) continue;
              final units = base.codeUnits;
              for (var k = 0; k <= hi - lo; k++) {
                final shifted = List<int>.of(units);
                shifted[shifted.length - 1] += k;
                out[lo + k] = String.fromCharCodes(shifted);
              }
            }
          }
          pending.clear();
        case 'begincodespacerange':
        case 'beginbfchar':
        case 'beginbfrange':
          pending.clear();
        default:
          break;
      }
    }
    return twoByte;
  }
}

/// Splits the Bengali characters Unicode writes two ways into their parts, so
/// a CMap entry and a font's `cmap` can be compared however either spells them:
/// `ো` as `ে` + `া`, `ৌ` as `ে` + `ৗ`, and the nukta letters as base + nukta.
String _decomposeBengali(String text) => text
    .replaceAll('\u09CB', '\u09C7\u09BE')
    .replaceAll('\u09CC', '\u09C7\u09D7')
    .replaceAll('\u09DC', '\u09A1\u09BC')
    .replaceAll('\u09DD', '\u09A2\u09BC')
    .replaceAll('\u09DF', '\u09AF\u09BC');
