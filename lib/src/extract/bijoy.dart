/// Bijoy / ANSI to Unicode conversion.
///
/// A Bijoy PDF stores Latin-1 bytes and relies on an 8-bit font to draw Bangla
/// glyphs for them, so the text layer is mojibake. Recovering Unicode is the
/// exact inverse of what `BanglaUnicodeMapper` does on the way out: undo the
/// glyph substitutions, then undo the visual reordering.
library;

import 'package:bangla_pdf/src/extract/bijoy_table.dart';

/// Bengali pre-base vowel signs. In Bijoy these are stored *before* the
/// consonant they belong to, matching how they render.
const Set<String> _preBaseMatras = <String>{'ি', 'ে', 'ৈ'};

/// U+09CD BENGALI SIGN VIRAMA.
const String _virama = '্';

/// The reph sequence a Bijoy `©` decodes to.
const String _reph = 'র্';

/// Consonants, for walking a cluster during reordering.
bool _isConsonant(String c) {
  if (c.isEmpty) return false;
  final r = c.runes.first;
  return (r >= 0x0995 && r <= 0x09B9) ||
      r == 0x09DC ||
      r == 0x09DD ||
      r == 0x09DF ||
      r == 0x09CE ||
      r == 0x09F0 ||
      r == 0x09F1;
}

/// Characters that legitimately follow a consonant inside its cluster.
bool _isClusterTail(String c) =>
    c == '়' || // nukta
    c == 'ঁ' || // candrabindu
    c == 'ং' || // anusvara
    c == 'ঃ'; // visarga

/// How strongly [text] looks like Bijoy ANSI rather than ordinary Latin.
///
/// Returns 0 for text with no Bijoy signal and approaches 1 for a pure Bijoy
/// run. Used to classify a PDF whose font name gives nothing away.
double bijoyConfidence(String text) {
  if (text.isEmpty) return 0;
  var bijoy = 0;
  var letters = 0;
  for (final rune in text.runes) {
    if (rune >= 0x0980 && rune <= 0x09FF) return 0; // already Unicode Bangla
    final c = String.fromCharCode(rune);
    if (rune > 0x20 && rune < 0x7F) letters++;
    // The Latin-1 supplement and Windows-1252 punctuation block carry most of
    // the Bijoy conjunct glyphs; plain English almost never uses them.
    if (rune >= 0xA0 || (rune >= 0x80 && rune <= 0x9F)) {
      bijoy++;
      letters++;
    } else if (_singleByteKeys.contains(c)) {
      bijoy++;
    }
  }
  if (letters == 0) return 0;
  return (bijoy / letters).clamp(0.0, 1.0);
}

final Set<String> _singleByteKeys = <String>{
  for (final (ansi, _) in kBijoyToUnicode)
    if (ansi.length == 1) ansi,
};

/// Font families that are Bijoy/ANSI rather than Unicode.
///
/// Name matching alone is unreliable — plenty of PDFs embed a subset with a
/// mangled name — so this only raises confidence; [bijoyConfidence] decides.
const List<String> kBijoyFontHints = <String>[
  'sutonny',
  'sutonnymj',
  'sutonnyomj',
  'sutonnyemj',
  'boishakhi',
  'chandrabati',
  'modhumati',
  'amarbangla',
  'shreelipi',
  'bijoy',
  'ansi',
  'proshika',
  'ekushey',
];

/// Whether [baseFont] names a known Bijoy/ANSI family.
bool looksLikeBijoyFontName(String baseFont) {
  final name = baseFont.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
  return kBijoyFontHints.any(name.contains);
}

/// Consonant + nukta pairs, emitted precomposed.
///
/// Both spellings exist in the wild and shape identically. Extraction settles
/// on the precomposed form because that is what Bangla keyboards produce and
/// what readers expect to see in a search box.
const Map<String, String> _nuktaComposition = <String, String>{
  '\u09A1\u09BC': '\u09DC', // da + nukta  -> rra   ড়
  '\u09A2\u09BC': '\u09DD', // dha + nukta -> rha   ঢ়
  '\u09AF\u09BC': '\u09DF', // ya + nukta  -> yya   য়
};

/// Converts one Bijoy/ANSI run to Unicode Bangla.
String bijoyToUnicode(String ansi) {
  if (ansi.isEmpty) return ansi;
  var text = _restoreLogicalOrder(_substitute(ansi));
  for (final entry in _nuktaComposition.entries) {
    text = text.replaceAll(entry.key, entry.value);
  }
  return text;
}

/// Greedy longest-match replacement using the inverted table.
String _substitute(String ansi) {
  final out = StringBuffer();
  var i = 0;
  outer:
  while (i < ansi.length) {
    for (final (key, value) in kBijoyToUnicode) {
      if (key.length <= ansi.length - i && ansi.startsWith(key, i)) {
        out.write(value);
        i += key.length;
        continue outer;
      }
    }
    out.write(ansi[i]);
    i++;
  }
  return out.toString();
}

/// Moves pre-base vowel signs and rephs back to logical order.
///
/// Bijoy stores text the way it looks: `ি` before its consonant, and the reph
/// after the cluster it sits above. Unicode stores it the way it is spoken.
String _restoreLogicalOrder(String visual) {
  final units = visual.split('');
  final out = <String>[];
  var i = 0;

  while (i < units.length) {
    final c = units[i];

    if (_preBaseMatras.contains(c)) {
      // Emit the following consonant cluster first, then the vowel sign.
      final cluster = _readCluster(units, i + 1);
      if (cluster.isEmpty) {
        out.add(c);
        i++;
        continue;
      }
      out
        ..addAll(cluster)
        ..add(c);
      i += 1 + cluster.length;
      continue;
    }

    out.add(c);
    i++;
  }

  // Two-part vowels are recomposed last: moving the reph can separate the
  // halves, so this has to run after the reordering rather than inline.
  return _recomposeTwoPartVowels(_moveRephs(out).join());
}

/// Rejoins `ে` + `া` into `ো` and `ে` + `ৗ` into `ৌ`.
String _recomposeTwoPartVowels(String text) => text
    .replaceAll('\u09C7\u09BE', '\u09CB')
    .replaceAll('\u09C7\u09D7', '\u09CC');

/// Reads a consonant cluster starting at [start]: a consonant, plus any
/// virama-joined consonants that follow it.
List<String> _readCluster(List<String> units, int start) {
  if (start >= units.length || !_isConsonant(units[start])) return const [];
  final cluster = <String>[units[start]];
  var i = start + 1;
  while (i < units.length) {
    if (_isClusterTail(units[i])) {
      cluster.add(units[i]);
      i++;
      continue;
    }
    if (units[i] == _virama &&
        i + 1 < units.length &&
        _isConsonant(units[i + 1])) {
      cluster
        ..add(units[i])
        ..add(units[i + 1]);
      i += 2;
      continue;
    }
    break;
  }
  return cluster;
}

/// Moves each `র্` that follows a cluster to the front of that cluster.
List<String> _moveRephs(List<String> units) {
  final text = units.join();
  if (!text.contains(_reph)) return units;

  final out = <String>[];
  for (var i = 0; i < units.length; i++) {
    // A reph decodes as র + virama. A ra-phala decodes as virama + র and can
    // be followed by another virama (গ্র্য), which looks identical unless the
    // preceding character is checked.
    final isReph = units[i] == 'র' &&
        i + 1 < units.length &&
        units[i + 1] == _virama &&
        (i == 0 || units[i - 1] != _virama);
    if (!isReph) {
      out.add(units[i]);
      continue;
    }
    i++; // consume the virama too

    // Walk back over the consonant cluster it belongs to and insert before it.
    var at = out.length;
    // Skip any vowel signs or marks the reph was written after.
    while (at > 0 && !_isConsonant(out[at - 1])) {
      at--;
    }
    // Then step over the cluster itself.
    while (at > 0 && _isConsonant(out[at - 1])) {
      at--;
      if (at >= 2 && out[at - 1] == _virama && _isConsonant(out[at - 2])) {
        at -= 1;
      } else {
        break;
      }
    }
    out.insertAll(at, <String>['র', _virama]);
  }
  return out;
}
