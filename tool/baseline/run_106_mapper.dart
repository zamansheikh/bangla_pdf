import 'dart:convert';
import 'dart:io';
import "mapper_106_snapshot.dart";

String hex(String s) => s.runes
    .map((r) => 'U+${r.toRadixString(16).toUpperCase().padLeft(4, '0')}')
    .join(' ');

void main(List<String> args) {
  final cases = jsonDecode(File(args[0]).readAsStringSync()) as List;
  final out = <Map<String, dynamic>>[];
  for (final c in cases) {
    final m = c as Map<String, dynamic>;
    final input = m['text'] as String;
    String? result;
    String? error;
    try {
      result = BanglaUnicodeMapper.encodeANSI(input);
    } catch (e) {
      error = '${e.runtimeType}: $e';
    }
    out.add({
      'id': m['id'],
      'category': m['category'],
      'input': input,
      'inputHex': hex(input),
      'output': result,
      'outputHex': result == null ? null : hex(result),
      'error': error,
    });
  }
  print(const JsonEncoder.withIndent('  ').convert(out));
}
