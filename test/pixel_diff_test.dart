// Compares what this package *draws* against what HarfBuzz draws.
//
// The corpus is already checked against HarfBuzz glyph by glyph and position by
// position, which is the stricter test of the two. This is the weaker but more
// honest one: it renders both and looks at the pixels, so a mistake in the
// layer *below* shaping — a wrong advance written into the font, a glyph drawn
// at the wrong offset, a PDF text operator built incorrectly — has somewhere to
// show up. Matching glyph ids cannot catch any of those.
//
// The trick that makes it meaningful: `hb-view` can emit PDF, so both sides are
// rasterised by the same poppler, at the same size, from the same font file.
// What is left after cropping to the ink is a like-for-like comparison rather
// than a fight between two rasterisers.
//
// Skips unless `hb-view` and `pdftoppm` are installed:
//   brew install harfbuzz poppler
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bangla_pdf/bangla_pdf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Font size both sides draw at, and the resolution both are rasterised at.
/// Large enough that a one-unit shaping error is several pixels wide.
const double _fontSize = 64;
const int _dpi = 150;

bool _has(String tool) =>
    Process.runSync('which', <String>[tool]).exitCode == 0;

/// An 8-bit greyscale image, as `pdftoppm -gray` writes it.
class Pgm {
  Pgm(this.width, this.height, this.pixels);

  final int width;
  final int height;
  final Uint8List pixels;

  /// Parses binary PGM (P5). Returns null for anything else.
  static Pgm? parse(Uint8List bytes) {
    var at = 0;
    List<int> token() {
      while (at < bytes.length && (bytes[at] <= 32 || bytes[at] == 0x23)) {
        if (bytes[at] == 0x23) {
          while (at < bytes.length && bytes[at] != 0x0A) {
            at++;
          }
        } else {
          at++;
        }
      }
      final start = at;
      while (at < bytes.length && bytes[at] > 32) {
        at++;
      }
      return bytes.sublist(start, at);
    }

    if (latin1.decode(token()) != 'P5') return null;
    final w = int.tryParse(latin1.decode(token()));
    final h = int.tryParse(latin1.decode(token()));
    final max = int.tryParse(latin1.decode(token()));
    if (w == null || h == null || max == null) return null;
    at++; // the single whitespace byte before the data
    if (at + w * h > bytes.length) return null;
    return Pgm(w, h, bytes.sublist(at, at + w * h));
  }

  /// Whether the pixel at (x, y) is ink. Anything not near-white counts, so
  /// antialiasing at the edge of a stroke is included on both sides alike.
  bool ink(int x, int y) =>
      x >= 0 &&
      y >= 0 &&
      x < width &&
      y < height &&
      pixels[y * width + x] < 200;

  /// The tightest box containing ink, or null when the page is blank.
  (int, int, int, int)? inkBox() {
    var left = width;
    var top = height;
    var right = -1;
    var bottom = -1;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (!ink(x, y)) continue;
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
    }
    return right < 0 ? null : (left, top, right, bottom);
  }
}

/// How much the ink of [a] and [b] overlaps, once both are cropped to their own
/// ink and laid on top of each other: shared ink over total ink.
///
/// The two are also nudged against each other by up to a couple of pixels and
/// the best fit is taken. Cropping aligns them only to the nearest whole pixel,
/// while the renderers place glyphs on sub-pixel boundaries; without the nudge,
/// a half-pixel offset shears away a big share of the overlap on a script made
/// of thin strokes, and every case looks wrong. What survives the nudge is a
/// real difference in what was drawn.
double inkOverlap(Pgm a, Pgm b) {
  final boxA = a.inkBox();
  final boxB = b.inkBox();
  if (boxA == null || boxB == null) return boxA == boxB ? 1.0 : 0.0;

  final width = <int>[boxA.$3 - boxA.$1, boxB.$3 - boxB.$1].reduce(max) + 1;
  final height = <int>[boxA.$4 - boxA.$2, boxB.$4 - boxB.$2].reduce(max) + 1;

  var best = 0.0;
  for (var dy = -2; dy <= 2; dy++) {
    for (var dx = -2; dx <= 2; dx++) {
      var shared = 0;
      var total = 0;
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final inA = a.ink(boxA.$1 + x, boxA.$2 + y);
          final inB = b.ink(boxB.$1 + x + dx, boxB.$2 + y + dy);
          if (inA && inB) shared++;
          if (inA || inB) total++;
        }
      }
      final score = total == 0 ? 1.0 : shared / total;
      if (score > best) best = score;
    }
  }
  return best;
}

int max(int a, int b) => a > b ? a : b;

/// Rasterises [pdf] with poppler and reads the result.
Pgm? rasterise(Directory dir, String name, Uint8List pdf) {
  final file = File('${dir.path}/$name.pdf')..writeAsBytesSync(pdf);
  final run = Process.runSync('pdftoppm', <String>[
    '-gray',
    '-r',
    '$_dpi',
    '-singlefile',
    file.path,
    '${dir.path}/$name',
  ]);
  if (run.exitCode != 0) return null;
  final out = File('${dir.path}/$name.pgm');
  if (!out.existsSync()) return null;
  return Pgm.parse(out.readAsBytesSync());
}

/// Draws [text] with this package, on a page big enough not to clip it.
Future<Uint8List> ourRendering(String text, pw.Font font) {
  final pdf = pw.Document();
  pdf.addPage(
    pw.Page(
      pageFormat: const PdfPageFormat(1400, 260, marginAll: 16),
      build: (context) => pw.Align(
        alignment: pw.Alignment.centerLeft,
        child: Text(
          text,
          banglaFont: font,
          style: const pw.TextStyle(fontSize: _fontSize),
        ),
      ),
    ),
  );
  return pdf.save();
}

/// Draws [text] with HarfBuzz, straight to PDF.
Uint8List? harfbuzzRendering(Directory dir, String fontPath, String text) {
  final out = '${dir.path}/hb-in.pdf';
  final run = Process.runSync('hb-view', <String>[
    // Without this, hb-view guesses the script from the buffer and picks
    // Latin for anything starting with Latin -- so "Hello বাংলাদেশ" is shaped
    // by the default shaper with no Indic reordering at all. That is an
    // artefact of the command-line tool, which does not itemise runs by
    // script the way a real text engine does, and comparing against it would
    // mean treating correct output as a defect.
    '--script=Beng',
    '--font-size=$_fontSize',
    '--margin=16',
    '-O',
    'pdf',
    fontPath,
    text,
    '-o',
    out,
  ]);
  if (run.exitCode != 0) return null;
  final file = File(out);
  return file.existsSync() ? file.readAsBytesSync() : null;
}

void main() {
  final available = _has('hb-view') && _has('pdftoppm');

  test('what we draw matches what HarfBuzz draws', () async {
    if (!available) {
      markTestSkipped(
          'needs hb-view and pdftoppm: brew install harfbuzz poppler');
      return;
    }

    const fontPath = 'test/fixtures/fonts/Kalpurush-Unicode.ttf';
    final font = BanglaPdf.loadFont(
      File(fontPath).readAsBytesSync().buffer.asByteData(),
    )!;

    final cases = (jsonDecode(
      File('test/corpus/bangla_cases.json').readAsStringSync(),
    ) as List<dynamic>)
        .cast<Map<String, dynamic>>();

    final dir = Directory.systemTemp.createTempSync('bangla_pixel');
    final scores = <double>[];
    final poor = <String>[];

    try {
      for (final testCase in cases) {
        final text = testCase['text'] as String;
        // A blank line has no ink to compare, and a very long one would be
        // clipped by the fixed page width rather than laid out differently.
        if (text.trim().isEmpty || text.length > 24) continue;

        final theirs = harfbuzzRendering(dir, fontPath, text);
        if (theirs == null) continue;
        final a = rasterise(dir, 'ours', await ourRendering(text, font));
        final b = rasterise(dir, 'theirs', theirs);
        if (a == null || b == null) continue;

        final overlap = inkOverlap(a, b);
        scores.add(overlap);
        if (overlap < 0.90) {
          poor.add('[${testCase['id']}] $text  overlap '
              '${(overlap * 100).toStringAsFixed(1)}%');
        }
      }

      expect(scores.length, greaterThan(100), reason: 'too few cases compared');
      final mean = scores.reduce((a, b) => a + b) / scores.length;

      // Identical shaping still leaves a hairline of disagreement along every
      // antialiased edge, so this can never be 1.0. What it can show is that no
      // case is drawing something structurally different.
      expect(
        mean,
        greaterThan(0.95),
        reason: 'mean ink overlap ${(mean * 100).toStringAsFixed(1)}%\n'
            '${poor.join('\n')}',
      );
      expect(
        poor,
        isEmpty,
        reason: 'cases drawing differently:\n${poor.join('\n')}',
      );
    } finally {
      dir.deleteSync(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
