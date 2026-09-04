import 'dart:convert';
import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

import 'package:bangla_pdf/bangla_pdf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

/// Inflates every stream in [bytes] and returns them as latin-1 text.
List<String> _streams(Uint8List bytes) {
  final text = latin1.decode(bytes, allowInvalid: true);
  final out = <String>[];
  final objects = RegExp(r'\d+ 0 obj(.*?)endobj', dotAll: true);
  for (final match in objects.allMatches(text)) {
    final body = match.group(1)!;
    final stream = RegExp(r'stream\r?\n(.*?)\r?\nendstream', dotAll: true)
        .firstMatch(body);
    if (stream == null) continue;
    final raw = Uint8List.fromList(latin1.encode(stream.group(1)!));
    if (body.contains('FlateDecode')) {
      try {
        out.add(latin1.decode(ZLibDecoder().convert(raw), allowInvalid: true));
      } catch (_) {
        // A stream we cannot inflate is not one we assert on.
      }
    } else {
      out.add(latin1.decode(raw, allowInvalid: true));
    }
  }
  return out;
}

Future<Uint8List> _render(List<String> lines) {
  final pdf = pw.Document();
  pdf.addPage(
    pw.Page(
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [for (final l in lines) Text(l, fontSize: 14)],
      ),
    ),
  );
  return pdf.save();
}

void main() {
  tearDown(BanglaPdf.reset);

  const sample = <String>[
    'আমার সোনার বাংলা, আমি তোমায় ভালোবাসি।',
    'ক্ষ্ম ঙ্ক্ষ ত্ত্ব চ্ছ্ব ম্ভ্র স্ত্র্য',
    'কর্ম ধর্ম বর্ষ পূর্ব শর্ত',
    'Hello বাংলাদেশ world! ৳১২,৫০০.০০',
  ];

  test('the PDF embeds a Type0 CID font with Identity-H encoding', () async {
    final bytes = await _render(sample);
    final text = latin1.decode(bytes, allowInvalid: true);
    expect(text, contains('/Type0'));
    expect(text, contains('/Identity-H'));
    expect(text, contains('/CIDFontType2'));
    expect(text, contains('/CIDToGIDMap'));
    expect(text, contains('/ToUnicode'));
  });

  test('every ToUnicode entry is real Unicode, never U+FFFD', () async {
    final bytes = await _render(sample);
    final cmaps = _streams(bytes).where((s) => s.contains('beginbfchar'));
    expect(cmaps, isNotEmpty, reason: 'no ToUnicode CMap was written');

    var mapped = 0;
    for (final cmap in cmaps) {
      for (final m
          in RegExp('<([0-9A-F]{4})> <([0-9A-F]*)>').allMatches(cmap)) {
        final value = m.group(2)!;
        for (var i = 0; i + 4 <= value.length; i += 4) {
          final unit = int.parse(value.substring(i, i + 4), radix: 16);
          expect(unit, isNot(0xFFFD),
              reason: 'CID ${m.group(1)} maps to U+FFFD');
          expect(unit, isNot(0), reason: 'CID ${m.group(1)} maps to NUL');
          mapped++;
        }
      }
    }
    expect(mapped, greaterThan(20));
  });

  test('the content stream carries /ActualText for every line', () async {
    final bytes = await _render(sample);
    final content = _streams(bytes).where((s) => s.contains('BDC')).join('\n');
    expect(content, contains('/ActualText'));
    // One span opened and closed per rendered line.
    final opens = RegExp('/ActualText').allMatches(content).length;
    final closes = RegExp(r'\bEMC\b').allMatches(content).length;
    expect(opens, sample.length);
    expect(closes, sample.length);
  });

  test('/ActualText round-trips the source text exactly', () async {
    final bytes = await _render(sample);
    final content =
        _streams(bytes).where((s) => s.contains('/ActualText')).join('\n');
    final recovered = <String>[];
    for (final m
        in RegExp('/ActualText <FEFF([0-9A-F]*)>').allMatches(content)) {
      final hex = m.group(1)!;
      final units = <int>[
        for (var i = 0; i + 4 <= hex.length; i += 4)
          int.parse(hex.substring(i, i + 4), radix: 16),
      ];
      recovered.add(String.fromCharCodes(units));
    }
    expect(recovered, sample);
  });

  test('no Bijoy ANSI text leaks into the shaped output', () async {
    final bytes = await _render(sample);
    final cmaps = _streams(bytes).where((s) => s.contains('beginbfchar'));
    // 1.0.6 mapped its glyphs to Latin-1 (Avgvi ‡mvbvi ...). Anything in the
    // Bengali block proves we are writing real Unicode instead.
    var bengali = 0;
    for (final cmap in cmaps) {
      for (final m in RegExp('<[0-9A-F]{4}> <([0-9A-F]*)>').allMatches(cmap)) {
        final value = m.group(1)!;
        for (var i = 0; i + 4 <= value.length; i += 4) {
          final unit = int.parse(value.substring(i, i + 4), radix: 16);
          if (unit >= 0x0980 && unit <= 0x09FE) bengali++;
        }
      }
    }
    expect(bengali, greaterThan(20),
        reason: 'the ToUnicode CMap should be full of Bengali codepoints');
  });

  test('legacy mode still produces a document', () async {
    BanglaPdf.configure(shapingMode: BanglaShapingMode.legacy);
    final bytes = await _render(sample);
    expect(bytes.length, greaterThan(1000));
  });
}
