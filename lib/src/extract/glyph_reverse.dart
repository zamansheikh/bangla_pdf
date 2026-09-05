/// Recovers text from glyph ids when a PDF gives no other way to.
///
/// A document with no `/ToUnicode` CMap and no `/ActualText` has thrown its
/// text away: all that survives is which glyph was drawn where. For Latin that
/// is nearly enough, because most glyphs are reachable from the font's `cmap`.
/// For Bengali it is not — a conjunct like `ক্ষ্ম` is a single glyph that no
/// codepoint maps to, produced by `GSUB` from several that do.
///
/// So this reads the font's own `GSUB` backwards. Every substitution it can
/// enumerate — single, multiple, alternate and ligature — is inverted into
/// "this output glyph came from those input glyphs", then resolved until every
/// glyph is expressed as codepoints the `cmap` knows.
///
/// The result is best-effort by nature and is only ever used as a last resort;
/// see [GlyphReverseMap.confidence].
library;

import 'package:bangla_pdf/src/ot/ot_font.dart';
import 'package:bangla_pdf/src/ot/ot_reader.dart';
import 'package:bangla_pdf/src/shaping/bengali_categories.dart';
import 'package:bangla_pdf/src/shaping/bengali_shaper.dart';

/// Features that build a form written virama-first.
///
/// A below-base or post-base consonant form — ba-phala `্ব`, ya-phala `্য` —
/// is typed virama then consonant, but a font lists its components the other
/// way round, because that is the order the shaper hands them over after
/// reordering. Reph and half forms are typed consonant then virama and must be
/// left alone, which is why this cannot be a blanket rule.
const _viramaFirstFeatures = <String>{'blwf', 'pstf', 'pref', 'vatu'};

/// One inverted substitution.
class _Source {
  const _Source(this.components, {required this.viramaFirst});
  final List<int> components;
  final bool viramaFirst;
}

/// Maps a font's glyph ids back to the text most likely to have produced them.
class GlyphReverseMap {
  GlyphReverseMap._(this._textForGid, this.confidence, this._shaper);

  /// Builds the map for [font]. Cheap enough to do once per font.
  factory GlyphReverseMap.build(OtFont font) {
    // Seed with what the cmap says outright. Lower codepoints win when several
    // map to one glyph, which keeps the base character rather than a variant.
    final direct = <int, int>{};
    for (final entry in font.cmap.entries) {
      final existing = direct[entry.value];
      if (existing == null || entry.key < existing) {
        direct[entry.value] = entry.key;
      }
    }

    // Invert every substitution the font declares, remembering which feature
    // each lookup belongs to so component order can be read correctly.
    final sources = <int, _Source>{};
    final gsub = font.gsub;
    if (gsub != null) {
      final byFeature = gsub.featureLookups(<String>['bng2', 'beng', 'DFLT']);
      final viramaFirst = <int>{
        for (final feature in _viramaFirstFeatures) ...?byFeature[feature],
      };
      for (var i = 0; i < gsub.lookupCount; i++) {
        _invertLookup(
          font.d,
          gsub.lookupOffset(i),
          sources,
          viramaFirst: viramaFirst.contains(i),
        );
      }
    }

    // Resolve each glyph to codepoints, expanding substitutions until only
    // cmap-reachable glyphs remain.
    final text = <int, String>{};
    var resolved = 0;
    final total = <int>{...direct.keys, ...sources.keys};
    for (final gid in total) {
      final runes = _resolve(gid, direct, sources, <int>{}, 0);
      if (runes == null) continue;
      text[gid] = String.fromCharCodes(runes);
      resolved++;
    }

    return GlyphReverseMap._(
      text,
      total.isEmpty ? 0.0 : resolved / total.length,
      BengaliShaper(font),
    );
  }

  final Map<int, String> _textForGid;

  /// The font's own shaper, used to check a decode by replaying it.
  final BengaliShaper _shaper;

  /// Share of the font's glyphs that could be expressed as text at all.
  ///
  /// Well under 1.0 for any real font: ornaments, dotted circles and internal
  /// forms have no text to give back.
  final double confidence;

  /// The text [gid] most likely stands for, or `null` when nothing is known.
  String? operator [](int gid) => _textForGid[gid];

  /// Whether anything at all could be recovered.
  bool get isEmpty => _textForGid.isEmpty;

  /// Turns a run of glyph ids in visual order into text in logical order.
  ///
  /// Decoding alone is not enough: Bengali draws a pre-base vowel sign before
  /// its consonant and a reph after the base it belongs to, so the glyphs
  /// arrive in an order no reader would type. This undoes both, which is the
  /// inverse of what the shaper did on the way in.
  String decodeRun(Iterable<int> gids) {
    final pieces = <String>[];
    for (final gid in gids) {
      final text = _textForGid[gid];
      if (text != null && text.isNotEmpty) pieces.add(text);
    }
    return _verify(_recompose(_toLogicalOrder(pieces)), gids.toList());
  }

  /// Confirms a decode by shaping it again, and repairs it when it fails.
  ///
  /// Inverting `GSUB` cannot always tell which side of a consonant its virama
  /// belongs on: a reph is typed `র` then virama, a ya-phala the other way
  /// round, and a font lists both the same way. Rather than guess from the
  /// feature a lookup happens to sit in, this shapes the candidate back and
  /// keeps it only if the glyphs come out as they went in.
  ///
  /// When they do not, the virama positions are flipped one combination at a
  /// time. The search is bounded, so a long run with many ambiguities keeps
  /// its unverified reading rather than costing exponential time.
  String _verify(String candidate, List<int> want) {
    if (_matches(candidate, want)) return candidate;

    final runes = candidate.runes.toList();
    final swappable = <int>[
      for (var i = 1; i < runes.length; i++)
        if (runes[i] == kVirama && categoryOf(runes[i - 1]) != IndicCategory.ra)
          i,
    ];
    if (swappable.isEmpty || swappable.length > 8) return candidate;

    for (var combo = 1; combo < (1 << swappable.length); combo++) {
      final trial = List<int>.of(runes);
      for (var b = 0; b < swappable.length; b++) {
        if (combo & (1 << b) == 0) continue;
        final at = swappable[b];
        final virama = trial[at];
        trial[at] = trial[at - 1];
        trial[at - 1] = virama;
      }
      final text = String.fromCharCodes(trial);
      if (_matches(text, want)) return text;
    }
    return candidate;
  }

  bool _matches(String text, List<int> want) {
    if (text.isEmpty) return false;
    final got = _shaper.shape(text).glyphs.map((g) => g.gid).toList();
    if (got.length != want.length) return false;
    for (var i = 0; i < got.length; i++) {
      if (got[i] != want[i]) return false;
    }
    return true;
  }
}

/// Reorders decoded pieces from visual to logical order.
String _toLogicalOrder(List<String> pieces) {
  final out = <String>[];
  var i = 0;
  while (i < pieces.length) {
    final piece = pieces[i];

    // A pre-base vowel sign is drawn first; in logical order it follows the
    // consonant it attaches to.
    if (_isPreBaseMatra(piece)) {
      var j = i + 1;
      // Skip over anything that is itself only a mark to find the base.
      while (j < pieces.length && _isPreBaseMatra(pieces[j])) {
        j++;
      }
      if (j < pieces.length && _isBaseLike(pieces[j])) {
        out.add(pieces[j]);
        for (var k = i; k < j; k++) {
          out.add(pieces[k]);
        }
        i = j + 1;
        continue;
      }
    }

    // A reph is drawn after the base and its below-base forms, but is typed
    // first: `র` + virama + the rest of the cluster.
    if (_isReph(piece) && out.isNotEmpty) {
      var start = out.length - 1;
      while (start > 0 && !_startsCluster(out[start])) {
        start--;
      }
      out.insert(start, piece);
      i++;
      continue;
    }

    out.add(piece);
    i++;
  }
  return out.join();
}

bool _isPreBaseMatra(String piece) {
  if (piece.isEmpty) return false;
  final first = piece.runes.first;
  return piece.runes.length == 1 &&
      categoryOf(first) == IndicCategory.matra &&
      defaultPositionOf(first) == IndicPosition.preMatra;
}

/// Whether [piece] is the reph form: `র` followed by a virama.
bool _isReph(String piece) {
  final runes = piece.runes.toList();
  return runes.length == 2 && runes[0] == 0x09B0 && runes[1] == kVirama;
}

/// Whether [piece] can carry a pre-base vowel sign.
bool _isBaseLike(String piece) {
  if (piece.isEmpty) return false;
  final category = categoryOf(piece.runes.first);
  return category == IndicCategory.consonant ||
      category == IndicCategory.ra ||
      category == IndicCategory.placeholder;
}

/// Whether [piece] starts a new syllable, used to find where a reph belongs.
bool _startsCluster(String piece) => _isBaseLike(piece);

/// Reads one lookup and records, for each output glyph, the glyphs it came
/// from. Extension lookups are unwrapped; contextual ones are skipped, because
/// their substitutions are performed by the nested lookups already covered.
void _invertLookup(
  OtData d,
  int? lookup,
  Map<int, _Source> out, {
  required bool viramaFirst,
}) {
  if (lookup == null || !d.has(lookup, 6)) return;
  final type = d.u16(lookup);
  final subtableCount = d.u16(lookup + 4);

  for (var i = 0; i < subtableCount; i++) {
    final sub = lookup + d.u16(lookup + 6 + 2 * i);
    switch (type) {
      case 1:
        _invertSingle(d, sub, out, viramaFirst);
      case 2:
        _invertMultiple(d, sub, out, viramaFirst);
      case 3:
        _invertAlternate(d, sub, out, viramaFirst);
      case 4:
        _invertLigature(d, sub, out, viramaFirst);
      case 7:
        // Extension: a type and a 32-bit offset to the real subtable.
        if (!d.has(sub, 8)) continue;
        final realType = d.u16(sub + 2);
        final realSub = sub + d.u32(sub + 4);
        switch (realType) {
          case 1:
            _invertSingle(d, realSub, out, viramaFirst);
          case 2:
            _invertMultiple(d, realSub, out, viramaFirst);
          case 3:
            _invertAlternate(d, realSub, out, viramaFirst);
          case 4:
            _invertLigature(d, realSub, out, viramaFirst);
          default:
            break;
        }
      default:
        break;
    }
  }
}

void _invertSingle(OtData d, int sub, Map<int, _Source> out, bool vf) {
  if (!d.has(sub, 6)) return;
  final format = d.u16(sub);
  final coverage = Coverage.parse(d, sub + d.u16(sub + 2));
  if (format == 1) {
    final delta = d.i16(sub + 4);
    for (final gid in coverage.glyphs) {
      out.putIfAbsent(
          (gid + delta) & 0xFFFF, () => _Source(<int>[gid], viramaFirst: vf));
    }
  } else if (format == 2) {
    final count = d.u16(sub + 4);
    var index = 0;
    for (final gid in coverage.glyphs) {
      if (index >= count) break;
      out.putIfAbsent(d.u16(sub + 6 + 2 * index),
          () => _Source(<int>[gid], viramaFirst: vf));
      index++;
    }
  }
}

void _invertMultiple(OtData d, int sub, Map<int, _Source> out, bool vf) {
  if (d.u16(sub) != 1 || !d.has(sub, 6)) return;
  final coverage = Coverage.parse(d, sub + d.u16(sub + 2));
  final count = d.u16(sub + 4);
  var index = 0;
  for (final gid in coverage.glyphs) {
    if (index >= count) break;
    final seq = sub + d.u16(sub + 6 + 2 * index);
    final glyphCount = d.u16(seq);
    // One glyph became several. Only the first carries the original text;
    // giving it to all of them would repeat the character.
    if (glyphCount > 0) {
      out.putIfAbsent(
          d.u16(seq + 2), () => _Source(<int>[gid], viramaFirst: vf));
      for (var g = 1; g < glyphCount; g++) {
        out.putIfAbsent(d.u16(seq + 2 + 2 * g),
            () => const _Source(<int>[], viramaFirst: false));
      }
    }
    index++;
  }
}

void _invertAlternate(OtData d, int sub, Map<int, _Source> out, bool vf) {
  if (d.u16(sub) != 1 || !d.has(sub, 6)) return;
  final coverage = Coverage.parse(d, sub + d.u16(sub + 2));
  final count = d.u16(sub + 4);
  var index = 0;
  for (final gid in coverage.glyphs) {
    if (index >= count) break;
    final set = sub + d.u16(sub + 6 + 2 * index);
    final altCount = d.u16(set);
    for (var a = 0; a < altCount; a++) {
      out.putIfAbsent(
          d.u16(set + 2 + 2 * a), () => _Source(<int>[gid], viramaFirst: vf));
    }
    index++;
  }
}

void _invertLigature(OtData d, int sub, Map<int, _Source> out, bool vf) {
  if (d.u16(sub) != 1 || !d.has(sub, 6)) return;
  final coverage = Coverage.parse(d, sub + d.u16(sub + 2));
  final setCount = d.u16(sub + 4);
  var index = 0;
  for (final first in coverage.glyphs) {
    if (index >= setCount) break;
    final set = sub + d.u16(sub + 6 + 2 * index);
    final ligCount = d.u16(set);
    for (var l = 0; l < ligCount; l++) {
      final lig = set + d.u16(set + 2 + 2 * l);
      final ligGlyph = d.u16(lig);
      final compCount = d.u16(lig + 2);
      if (compCount == 0) continue;
      final components = <int>[
        first,
        for (var c = 0; c < compCount - 1; c++) d.u16(lig + 4 + 2 * c),
      ];
      out.putIfAbsent(ligGlyph, () => _Source(components, viramaFirst: vf));
    }
    index++;
  }
}

/// Puts a trailing virama back in front of the consonant it kills.
///
/// A font lists a half or phala form's components consonant-first — the
/// ya-phala `্য` is stored as `য` then virama — because that is the order the
/// shaper feeds it after reordering. Typing order is the other way round.
List<int> _fixViramaOrder(List<int> runes) {
  if (runes.length >= 2 && runes.last == kVirama) {
    final out = List<int>.of(runes);
    final last = out.removeLast();
    out.insert(out.length - 1, last);
    return out;
  }
  return runes;
}

/// Recomposes the pairs Unicode writes as one character.
///
/// The shaper splits `ো` into `ে` + `া` and composes `ড` + nukta into `ড়`
/// before it runs, so both have to be undone on the way back.
String _recompose(String text) {
  final runes = text.runes.toList();
  final out = <int>[];
  var i = 0;
  while (i < runes.length) {
    final rune = runes[i];
    final next = i + 1 < runes.length ? runes[i + 1] : -1;

    // Two-part vowel signs: `ে` + `া` is written `ো`.
    var joined = false;
    for (final entry in kMatraDecomposition.entries) {
      if (entry.value[0] == rune && entry.value[1] == next) {
        out.add(entry.key);
        i += 2;
        joined = true;
        break;
      }
    }
    if (joined) continue;

    // Consonant + nukta: `ড` + `়` is written `ড়`.
    if (next == 0x09BC && kNuktaComposition.containsKey(rune)) {
      out.add(kNuktaComposition[rune]!);
      i += 2;
      continue;
    }

    out.add(rune);
    i++;
  }
  return String.fromCharCodes(out);
}

/// Expands [gid] into codepoints, following substitutions as far as needed.
///
/// [seen] breaks the cycles a font can declare — a ligature whose component
/// substitutes back to itself — and [depth] bounds pathological nesting.
List<int>? _resolve(
  int gid,
  Map<int, int> direct,
  Map<int, _Source> sources,
  Set<int> seen,
  int depth,
) {
  if (depth > 8 || !seen.add(gid)) return null;
  try {
    // A codepoint of its own wins over any substitution that also produces
    // this glyph: `ৎ` is built from ত + virama, but it is its own character.
    final own = direct[gid];
    if (own != null) return <int>[own];

    final source = sources[gid];
    if (source != null) {
      if (source.components.isEmpty) return const <int>[]; // no text
      final out = <int>[];
      for (final component in source.components) {
        final part = _resolve(component, direct, sources, seen, depth + 1);
        if (part == null) return null;
        out.addAll(part);
      }
      return source.viramaFirst ? _fixViramaOrder(out) : out;
    }
    return null;
  } finally {
    seen.remove(gid);
  }
}
