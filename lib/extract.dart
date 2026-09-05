/// Bangla text extraction from PDFs.
///
/// A separate library on purpose: importing `package:bangla_pdf/bangla_pdf.dart`
/// to *generate* a PDF costs nothing from this file.
///
/// ```dart
/// import 'package:bangla_pdf/extract.dart';
///
/// final result = BanglaPdfExtractor.extract(bytes);
/// print(result.encodingDetected);   // unicode | bijoy | mixed | none
/// print(result.text);
/// ```
///
/// It handles three kinds of document:
///
///  * **Unicode** — a modern PDF with a `/ToUnicode` CMap, or `/ActualText`
///    spans like the ones this package writes. Read directly.
///  * **Bijoy / ANSI** — the legacy encoding behind most Bangladeshi
///    government and newspaper PDFs. The text layer is Latin-1 mojibake
///    (`Avgvi ‡mvbvi evsjv`); it is converted back to Unicode per text run,
///    because only the run's font can tell Bijoy bytes from real English.
///  * **Scanned** — no text layer at all. Reported as
///    [BanglaTextEncoding.none], with [BanglaPdfExtractor.ocrHook] available
///    to plug in an OCR engine.
library;

import 'dart:typed_data';

import 'package:bangla_pdf/src/extract/bijoy.dart';
import 'package:bangla_pdf/src/extract/content_stream.dart';
import 'package:bangla_pdf/src/extract/font_info.dart';
import 'package:bangla_pdf/src/extract/pdf_object.dart';
import 'package:bangla_pdf/src/extract/pdf_reader.dart';

export 'package:bangla_pdf/src/extract/bijoy.dart' show bijoyToUnicode;

/// How the Bangla in a document was encoded.
enum BanglaTextEncoding {
  /// Real Unicode, read straight out of the text layer.
  unicode,

  /// Legacy Bijoy/ANSI, converted back to Unicode.
  bijoy,

  /// Both, in different runs — common when a Bijoy document was partly
  /// re-typed.
  mixed,

  /// No text layer: a scan, or a document whose text could not be read.
  none,
}

/// One extracted page.
class ExtractedPage {
  const ExtractedPage({
    required this.number,
    required this.text,
    required this.encodingDetected,
    required this.hasImages,
  });

  /// 1-based page number.
  final int number;

  /// The page's text, in reading order.
  final String text;

  /// How this page's Bangla was encoded.
  final BanglaTextEncoding encodingDetected;

  /// Whether the page draws any image.
  final bool hasImages;
}

/// The result of extracting a document.
class ExtractionResult {
  const ExtractionResult({
    required this.text,
    required this.pages,
    required this.encodingDetected,
    required this.confidence,
    this.isEncrypted = false,
    this.isLocked = false,
  });

  /// Every page's text, joined by a blank line.
  final String text;

  /// Per-page results.
  final List<ExtractedPage> pages;

  /// How the document as a whole was encoded.
  final BanglaTextEncoding encodingDetected;

  /// Rough confidence in the extraction, 0 to 1.
  ///
  /// 1 means the document told us its text outright (`/ActualText` or a
  /// complete `/ToUnicode` CMap). Lower values mean more was inferred — a
  /// Bijoy conversion, or a font with no usable mapping.
  final double confidence;

  /// Whether the document is encrypted.
  ///
  /// Encryption on its own is no obstacle: most protected PDFs carry an owner
  /// password and an empty user password, and are decrypted transparently. See
  /// [isLocked] for the case that actually blocks reading.
  final bool isEncrypted;

  /// Whether the document is encrypted and could not be opened.
  ///
  /// True when a password is genuinely required, or the document uses a
  /// security handler this does not implement. The text will be empty.
  final bool isLocked;

  /// Whether any Bangla was found.
  bool get hasBangla => RegExp('[ঀ-৿]').hasMatch(text);

  @override
  String toString() =>
      'ExtractionResult(${pages.length} pages, $encodingDetected, '
      'confidence ${confidence.toStringAsFixed(2)})';
}

/// Called for a page with no text layer, to supply text from elsewhere.
///
/// The extractor does not bundle OCR. Wire in whatever engine you already
/// have — Tesseract with the `ben` language data is the usual choice:
///
/// ```dart
/// BanglaPdfExtractor.extract(
///   bytes,
///   ocrHook: (page) async => runTesseract(page.number, language: 'ben'),
/// );
/// ```
typedef BanglaOcrHook = String? Function(ExtractedPage page);

/// Reads Bangla text out of a PDF.
class BanglaPdfExtractor {
  BanglaPdfExtractor._();

  /// Extracts [bytes].
  ///
  /// Never throws: an unreadable document comes back as an empty result with
  /// [BanglaTextEncoding.none] rather than an exception, because the documents
  /// most worth extracting are also the most likely to be damaged.
  /// [password] opens a document that needs one. Most protected PDFs do not:
  /// they carry an owner password and an empty user password, so they are
  /// decrypted without it.
  static ExtractionResult extract(
    Uint8List bytes, {
    BanglaOcrHook? ocrHook,
    String password = '',
  }) {
    final reader = PdfReader.open(bytes, password: password);
    if (reader == null) {
      return const ExtractionResult(
        text: '',
        pages: <ExtractedPage>[],
        encodingDetected: BanglaTextEncoding.none,
        confidence: 0,
      );
    }

    final pages = <ExtractedPage>[];
    var sawUnicode = false;
    var sawBijoy = false;
    var certainty = 0.0;
    var counted = 0;

    final pageDicts = reader.pages();
    for (var i = 0; i < pageDicts.length; i++) {
      final page = pageDicts[i];
      final fonts = _fontsOf(reader, page);
      final content = walkContentStream(reader.contentOf(page), fonts);

      final buffer = StringBuffer();
      var pageUnicode = false;
      var pageBijoy = false;
      var mapped = 0;
      var unmapped = 0;

      double? lastY;
      var lastObject = -1;
      for (final run in content.runs) {
        if (run.text.isEmpty) continue;
        if (lastY != null && (lastY - run.y).abs() > run.fontSize * 0.4) {
          // A change in device-space Y is a new line.
          buffer.write('\n');
        } else if (lastY != null &&
            run.objectIndex != lastObject &&
            _needsSpaceBetween(buffer.toString(), run.text)) {
          // Same line, new text object: a word-by-word producer drew a space
          // by repositioning rather than by emitting one.
          buffer.write(' ');
        }
        lastY = run.y;
        lastObject = run.objectIndex;

        final font = run.font;
        // Only a run's own font can say whether its bytes are Bijoy: the byte
        // 'e' is English "e" in one font and ব in another.
        final treatAsBijoy =
            font != null && font.isBijoy && bijoyConfidence(run.text) > 0;
        if (treatAsBijoy) {
          buffer.write(bijoyToUnicode(run.text));
          pageBijoy = true;
          mapped++;
        } else {
          buffer.write(run.text);
          if (RegExp('[ঀ-৿]').hasMatch(run.text)) pageUnicode = true;
          if (font == null || font.toUnicode.isEmpty) {
            unmapped++;
          } else {
            mapped++;
          }
        }
      }

      var text = buffer.toString().trim();
      final encoding = _classify(pageUnicode, pageBijoy, text);

      var pageResult = ExtractedPage(
        number: i + 1,
        text: text,
        encodingDetected: encoding,
        hasImages: content.imageCount > 0,
      );

      if (text.isEmpty && ocrHook != null) {
        final recovered = ocrHook(pageResult);
        if (recovered != null && recovered.isNotEmpty) {
          text = recovered;
          pageResult = ExtractedPage(
            number: i + 1,
            text: text,
            encodingDetected: BanglaTextEncoding.unicode,
            hasImages: pageResult.hasImages,
          );
        }
      }

      pages.add(pageResult);
      if (pageUnicode) sawUnicode = true;
      if (pageBijoy) sawBijoy = true;

      if (text.isNotEmpty) {
        counted++;
        certainty += content.actualTextUsed
            ? 1.0
            : (mapped + unmapped == 0
                ? 0.0
                : mapped / (mapped + unmapped) * (pageBijoy ? 0.85 : 1.0));
      }
    }

    final joined =
        pages.map((p) => p.text).where((t) => t.isNotEmpty).join('\n\n');

    return ExtractionResult(
      text: joined,
      pages: pages,
      encodingDetected: _classify(sawUnicode, sawBijoy, joined),
      confidence: counted == 0 ? 0.0 : (certainty / counted).clamp(0.0, 1.0),
      isEncrypted: reader.isEncrypted,
      isLocked: reader.isLocked,
    );
  }

  /// Punctuation that binds to the word before it, so no space is inserted.
  static const String _bindsLeft = '.,:;!?)]}»%/\u0964\u0965\u2019\u201D';

  /// Punctuation that binds to the word after it.
  static const String _bindsRight = '([{«/\u2018\u201C';

  /// Whether a space belongs between two runs drawn as separate text objects.
  static bool _needsSpaceBetween(String before, String next) {
    if (before.isEmpty || next.isEmpty) return false;
    if (before.endsWith(' ') || before.endsWith('\n')) return false;
    if (next.startsWith(' ')) return false;
    final last = before[before.length - 1];
    if (_bindsLeft.contains(next[0])) return false;
    if (_bindsRight.contains(last)) return false;
    // A separator *between digits* is part of a number or a date rather than
    // the end of a sentence: ৪৬.০০, ০১/০৯/২০২৬, ৳১২,৫০০. It has to be flanked
    // by digits, or "তারিখ:০১" would lose its space too.
    if ('./,:-'.contains(last) &&
        before.length >= 2 &&
        _isDigit(before.codeUnitAt(before.length - 2)) &&
        _isDigit(next.codeUnitAt(0))) {
      return false;
    }
    return true;
  }

  static bool _isDigit(int c) =>
      (c >= 0x30 && c <= 0x39) || (c >= 0x09E6 && c <= 0x09EF);

  static BanglaTextEncoding _classify(bool unicode, bool bijoy, String text) {
    if (text.trim().isEmpty) return BanglaTextEncoding.none;
    if (unicode && bijoy) return BanglaTextEncoding.mixed;
    if (bijoy) return BanglaTextEncoding.bijoy;
    return BanglaTextEncoding.unicode;
  }

  static Map<String, FontInfo> _fontsOf(PdfReader reader, PdfDictObj page) {
    final out = <String, FontInfo>{};
    final resources = reader.resolve(page['Resources']);
    if (resources is! PdfDictObj) return out;
    final fonts = reader.resolve(resources['Font']);
    if (fonts is! PdfDictObj) return out;
    for (final entry in fonts.entries.entries) {
      final dict = reader.resolve(entry.value);
      if (dict is PdfDictObj) {
        out[entry.key] = FontInfo.parse(reader, dict);
      }
    }
    return out;
  }
}
