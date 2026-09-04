import 'dart:io';
import "mapper_106_snapshot.dart";

// Replicates FixingUtils.getAutoLocalizedSpans run-splitting from 1.0.6.
void main() {
  final probes = <String>[
    'কর্ম',
    'কর্ম ',
    'কর্ম।',
    'বর্ষ',
    'আমার কর্ম',
    'কর্ম করি',
    'দুর্গা',
    'র্ক',
    'কর্মচারী',
    'ধর্ম',
    'সর্বোচ্চ',
    'কার্যক্রম',
    'পূর্ব',
    'নির্বাচন',
    'অর্থনীতি',
    'কর্তৃপক্ষ',
    'বিশ্ববিদ্যালয়',
    'শর্ত',
    'পরিবর্তন',
  ];
  final banglaRegex = RegExp(r'[ঀ-৿।॥]+ *');
  for (final text in probes) {
    final results = <String>[];
    var crashed = false;
    for (final m in banglaRegex.allMatches(text)) {
      try {
        results.add(BanglaUnicodeMapper.encodeANSI(m.group(0)!));
      } catch (e) {
        crashed = true;
        results.add('<<CRASH ${e.runtimeType}>>');
      }
    }
    stdout.writeln(
        '${crashed ? "CRASH " : "ok    "} ${text.padRight(20)} -> ${results.join("|")}');
  }
}
