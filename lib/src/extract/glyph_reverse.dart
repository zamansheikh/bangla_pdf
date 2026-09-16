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
  ///
  /// [documentText] is what the document itself claims each glyph id stands
  /// for, when it says anything. It is never taken at its word — see
  /// [_learnPrunedSigns] for the one narrow use made of it.
  factory GlyphReverseMap.build(OtFont font,
      {Map<int, List<String>>? documentText}) {
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

    if (documentText != null) {
      _learnPrunedSigns(direct, sources, documentText);
    }

    // Resolve each glyph to codepoints, expanding substitutions until only
    // cmap-reachable glyphs remain.
    final text = <int, String>{};
    var resolved = 0;
    final total = <int>{...direct.keys, ...sources.keys};
    for (final gid in total) {
      final runes = _resolve(gid, direct, sources, <int>{}, 0);
      if (runes == null) continue;
      text[gid] = String.fromCharCodes(_preBaseMatraLast(runes));
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
  ///
  /// [fallback] supplies text for a glyph the font itself cannot name — one a
  /// subsetter left in the font but pruned from its `cmap`, as Word does with
  /// `ূ`. It is asked only for those, so a document's mapping never overrides
  /// what the font says about a glyph it does know.
  String decodeRun(Iterable<int> gids,
      {String? Function(int index)? fallback}) {
    final list = gids.toList();
    final pieces = <String>[];
    for (var i = 0; i < list.length; i++) {
      final text = _textForGid[list[i]] ?? fallback?.call(i);
      if (text != null && text.isNotEmpty) pieces.add(text);
    }
    return _verify(
        _recompose(_signsAfterConjuncts(_toLogicalOrder(pieces))), list);
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
String _toLogicalOrder(List<String> drawn) {
  final split = _splitFusedReph(drawn);
  final pieces = <String>[
    for (var i = 0; i < split.length; i++)
      if (!(split[i].trim().isEmpty &&
          _startsWithDependent(i + 1 < split.length ? split[i + 1] : null)))
        split[i],
  ];
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
        // The sign follows the whole consonant cluster, not just its first
        // glyph: a phala or nukta drawn after the base belongs before it, or
        // লক্ষ্যে comes back as লক্ষে্য.
        var end = j + 1;
        while (end < pieces.length && _extendsCluster(pieces[end])) {
          end++;
        }
        for (var k = j; k < end; k++) {
          out.add(pieces[k]);
        }
        for (var k = i; k < j; k++) {
          out.add(pieces[k]);
        }
        i = end;
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

/// Puts a pre-base vowel sign that leads a ligature's components after them.
///
/// Many fonts fuse a pre-base vowel sign with its consonant into one glyph —
/// `টি` is a single glyph in NikoshBAN — and they build it after reordering, so
/// its components are listed in drawing order, `ি` first. Read back as they
/// stand they give `িট`, which nobody types. A single glyph covers one cluster,
/// so the sign belongs at the end of it.
List<int> _preBaseMatraLast(List<int> runes) {
  if (runes.length < 2) return runes;
  final first = runes.first;
  if (categoryOf(first) != IndicCategory.matra ||
      defaultPositionOf(first) != IndicPosition.preMatra) {
    return runes;
  }
  return <int>[...runes.skip(1), first];
}

/// Separates a reph a font has fused with the mark after it.
///
/// Fonts commonly draw `র্` and a following vowel sign as one glyph — `র্ী` in
/// শিক্ষার্থী — so the piece is not a bare reph and would stay where it was
/// drawn. Split off, the reph moves to the front of its cluster and the sign
/// stays behind the base.
List<String> _splitFusedReph(List<String> pieces) {
  final out = <String>[];
  for (final piece in pieces) {
    final runes = piece.runes.toList();
    if (runes.length > 2 &&
        runes[0] == 0x09B0 &&
        runes[1] == kVirama &&
        runes.skip(2).every(_isMark)) {
      out
        ..add(String.fromCharCodes(<int>[0x09B0, kVirama]))
        ..add(String.fromCharCodes(runes.skip(2)));
    } else {
      out.add(piece);
    }
  }
  return out;
}

/// Whether [rune] is a dependent sign rather than a letter of its own.
bool _isMark(int rune) {
  final category = categoryOf(rune);
  return category == IndicCategory.matra ||
      category == IndicCategory.syllableModifier ||
      category == IndicCategory.nukta;
}

/// Whether [piece], drawn after a base consonant, is still part of its
/// cluster ahead of any vowel sign: a phala or other virama-led form, or a
/// nukta.
bool _extendsCluster(String piece) {
  if (piece.isEmpty) return false;
  final first = piece.runes.first;
  return first == kVirama || categoryOf(first) == IndicCategory.nukta;
}

/// Whether [piece] begins with something that cannot begin a word — a virama
/// or a dependent sign.
///
/// A blank piece in front of one is not a word break. Fonts often give the
/// zero-width joiner the same glyph as a space, so `ল‍্যা`, typed with a joiner,
/// is drawn as ল, space glyph, ্যা; read back literally it becomes `ল ্যা`.
bool _startsWithDependent(String? piece) {
  if (piece == null || piece.isEmpty) return false;
  final first = piece.runes.first;
  // A pre-base vowel sign is the exception: it is drawn before its consonant,
  // so in drawing order it does begin a word — the space before থেকে is real.
  if (categoryOf(first) == IndicCategory.matra &&
      defaultPositionOf(first) == IndicPosition.preMatra) {
    return false;
  }
  return first == kVirama || _isMark(first);
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
/// Recovers the characters of vowel signs a subsetter pruned from the `cmap`,
/// using the document's own text — but only where the font vouches for it.
///
/// Word's subsets drop `ৃ`, `ূ` and friends from the `cmap` while keeping their
/// glyphs and every ligature built from them. Such a glyph cannot be read back,
/// and neither can `তৃ`, one glyph built from ত and it. The document's
/// `/ToUnicode` does name them, but that is exactly the mapping that could not
/// be trusted in the first place: for `তৃ` Word wrote `র্ত`, having first met
/// the glyph in `কর্তৃপক্ষ`, where the reph is drawn after it.
///
/// So a claim counts only when it fits the ligature's structure. `তৃ` is built
/// from `[ত, ?]`; a claim for it must be ত followed by one dependent sign, and
/// `র্ত` is not. Claims that do fit — `পৃ`, `কৃ`, `গৃ` from the same document —
/// vote on what `?` is, and a sign is adopted only when the votes clearly
/// agree. A glyph shown on its own may vote too, if the document names it as a
/// single sign. Nothing else about the document's mapping is used.
void _learnPrunedSigns(
  Map<int, int> direct,
  Map<int, _Source> sources,
  Map<int, List<String>> documentText,
) {
  final votes = <int, Map<int, int>>{};
  void vote(int gid, int codepoint) {
    final tally = votes.putIfAbsent(gid, () => <int, int>{});
    tally[codepoint] = (tally[codepoint] ?? 0) + 1;
  }

  int? singleSign(String claim) {
    final runes = decomposeBengali(claim).runes.toList();
    if (runes.length != 1) return null;
    return isDependentSign(runes.single) ? runes.single : null;
  }

  // Ligatures with exactly one component the font cannot name.
  for (final MapEntry(key: gid, value: source) in sources.entries) {
    if (source.components.length < 2) continue;
    final claims = documentText[gid];
    if (claims == null) continue;
    final parts = [
      for (final c in source.components)
        _resolve(c, direct, sources, <int>{}, 0),
    ];
    final unknown = [
      for (var i = 0; i < parts.length; i++)
        if (parts[i] == null) i,
    ];
    if (unknown.length != 1) continue;
    final at = unknown.single;
    final missing = source.components[at];
    if (direct.containsKey(missing)) continue;
    final before = decomposeBengali(String.fromCharCodes(
        [for (final part in parts.sublist(0, at)) ...part!]));
    final after = decomposeBengali(String.fromCharCodes(
        [for (final part in parts.sublist(at + 1)) ...part!]));
    for (final claim in claims) {
      final whole = decomposeBengali(claim);
      if (whole.length <= before.length + after.length) continue;
      if (!whole.startsWith(before) || !whole.endsWith(after)) continue;
      final sign = singleSign(
          whole.substring(before.length, whole.length - after.length));
      if (sign != null) vote(missing, sign);
    }
  }

  // A glyph the font knows nothing about, named by the document as one sign.
  for (final MapEntry(key: gid, value: claims) in documentText.entries) {
    if (direct.containsKey(gid) || sources.containsKey(gid)) continue;
    for (final claim in claims) {
      final sign = singleSign(claim);
      if (sign != null) vote(gid, sign);
    }
  }

  for (final MapEntry(key: gid, value: tally) in votes.entries) {
    final ranked = tally.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final best = ranked.first;
    final others = ranked.skip(1).fold(0, (sum, e) => sum + e.value);
    // Clear agreement only: a swapped claim can slip through the structure
    // test when a sign is exchanged with a sign, and must not decide it.
    if (best.value >= 2 * others && best.value > others) {
      direct[gid] = best.key;
    }
  }
}

/// Moves a vowel sign that precedes a virama to after the consonant it joins.
///
/// A vowel sign follows the whole cluster in Unicode, so a sign directly
/// before a virama is never a spelling. Fonts draw one anyway: `ন্যূ` is shown
/// as `নূ` with the ya-phala after it, and read back in drawing order that is
/// `নূ্য`.
String _signsAfterConjuncts(String text) => text.replaceAllMapped(
      _signBeforeConjunct,
      (m) => '${m[2]}${m[1]}',
    );

final RegExp _signBeforeConjunct = RegExp(
  r'([\u09BE-\u09CC\u09D7]+)((?:\u09CD[\u0995-\u09B9\u09DC-\u09DF]\u09BC?)+)',
  unicode: true,
);

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
