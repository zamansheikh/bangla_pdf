/// The Bengali (`bng2`) OpenType shaper.
///
/// Follows the OpenType Indic shaping model: normalise, split into syllables,
/// find the base consonant, reorder within the syllable, apply the basic GSUB
/// features one at a time under per-glyph masks, reorder the reph, then apply
/// the presentation features and GPOS.
///
/// It is validated case-by-case against HarfBuzz's `hb-shape` over the project
/// corpus; see `tool/dev/diff_hb.dart`.
library;

import 'dart:io' show Platform;

import 'package:bangla_pdf/src/ot/glyph_buffer.dart';
import 'package:bangla_pdf/src/ot/gpos.dart';
import 'package:bangla_pdf/src/ot/gsub.dart';
import 'package:bangla_pdf/src/ot/ot_font.dart';
import 'package:bangla_pdf/src/shaping/bengali_categories.dart';

/// Feature mask bits. A glyph may only be touched by a feature whose bit it
/// carries; features marked global are set on every glyph.
class _F {
  static const int locl = 1 << 0;
  static const int ccmp = 1 << 1;
  static const int nukt = 1 << 2;
  static const int akhn = 1 << 3;
  static const int rphf = 1 << 4;
  static const int rkrf = 1 << 5;
  static const int pref = 1 << 6;
  static const int blwf = 1 << 7;
  static const int abvf = 1 << 8;
  static const int half = 1 << 9;
  static const int pstf = 1 << 10;
  static const int vatu = 1 << 11;
  static const int cjct = 1 << 12;
  static const int init = 1 << 13;
  static const int pres = 1 << 14;
  static const int abvs = 1 << 15;
  static const int blws = 1 << 16;
  static const int psts = 1 << 17;
  static const int haln = 1 << 18;
  static const int calt = 1 << 19;
  static const int clig = 1 << 20;
  static const int rclt = 1 << 21;
  static const int rlig = 1 << 22;

  /// Features every glyph is eligible for.
  static const int global = locl |
      ccmp |
      nukt |
      akhn |
      rkrf |
      vatu |
      cjct |
      pres |
      abvs |
      blws |
      psts |
      haln |
      calt |
      clig |
      rclt |
      rlig;
}

/// Feature tag paired with its mask bit, in the order the Indic model applies
/// them.
const List<(String, int)> _basicFeatures = <(String, int)>[
  ('nukt', _F.nukt),
  ('akhn', _F.akhn),
  ('rphf', _F.rphf),
  ('rkrf', _F.rkrf),
  ('pref', _F.pref),
  ('blwf', _F.blwf),
  ('abvf', _F.abvf),
  ('half', _F.half),
  ('pstf', _F.pstf),
  ('vatu', _F.vatu),
  ('cjct', _F.cjct),
];

const List<(String, int)> _presentationFeatures = <(String, int)>[
  ('init', _F.init),
  ('pres', _F.pres),
  ('abvs', _F.abvs),
  ('blws', _F.blws),
  ('psts', _F.psts),
  ('haln', _F.haln),
];

const List<(String, int)> _finalFeatures = <(String, int)>[
  ('rlig', _F.rlig),
  ('rclt', _F.rclt),
  ('calt', _F.calt),
  ('clig', _F.clig),
];

/// One indivisible unit of shaped text: the glyphs of a single syllable and
/// the exact source substring they came from.
///
/// Bengali reorders glyphs within a syllable, so glyph order is not text order.
/// Emitting the source text per cluster as PDF `/ActualText` is what makes
/// copy/paste return the original Unicode in the right order.
class ShapedCluster {
  const ShapedCluster({
    required this.text,
    required this.glyphStart,
    required this.glyphEnd,
  });

  /// The source substring this cluster renders.
  final String text;

  /// First glyph index in [ShapedRun.glyphs], inclusive.
  final int glyphStart;

  /// Last glyph index, exclusive.
  final int glyphEnd;
}

/// A shaped run: glyphs in visual order plus the text they came from.
class ShapedRun {
  ShapedRun({
    required this.glyphs,
    required this.source,
    required this.unitsPerEm,
    this.clusters = const <ShapedCluster>[],
  });

  /// Glyphs in visual (left-to-right) order.
  final List<GlyphInfo> glyphs;

  /// The original source string, unmodified.
  final String source;

  /// Font design units per em, for scaling advances.
  final int unitsPerEm;

  /// Syllable groups, in visual order, covering every glyph.
  final List<ShapedCluster> clusters;

  /// Total advance in font units.
  int get advance => glyphs.fold<int>(0, (sum, g) => sum + g.xAdvance);
}

/// Shapes Bengali text with a font's own GSUB/GPOS tables.
class BengaliShaper {
  BengaliShaper(this.font)
      : _gsub = font.gsub == null ? null : GsubEngine(font, font.gsub!),
        _gpos = font.gpos == null ? null : GposEngine(font, font.gpos!) {
    _gsubFeatures = font.gsub?.featureLookups(_scripts) ?? const {};
    _gposFeatures = font.gpos?.featureLookups(_scripts) ?? const {};
  }

  static const List<String> _scripts = <String>['bng2', 'beng'];

  /// The font being shaped with.
  final OtFont font;

  final GsubEngine? _gsub;
  final GposEngine? _gpos;
  late final Map<String, List<int>> _gsubFeatures;
  late final Map<String, List<int>> _gposFeatures;

  /// Whether this font carries the layout data the shaper needs.
  bool get canShape => _gsub != null && font.hasBengaliCoverage;

  int? _viramaGlyph;
  final Map<int, int> _consonantPositionCache = <int, int>{};

  /// Shapes [text] and returns glyphs in visual order.
  ShapedRun shape(String text) {
    var units = _normalise(text);
    if (units.isEmpty) {
      return ShapedRun(
        glyphs: const <GlyphInfo>[],
        source: text,
        unitsPerEm: font.unitsPerEm,
      );
    }

    // A syllable that opens with a mark has no base to hang it on. Unicode
    // says to show it on a dotted circle, which is what every other shaper
    // does; without it a stray matra silently vanishes.
    units = _insertDottedCircles(units);

    final buf = <GlyphInfo>[];
    for (final u in units) {
      buf.add(
        GlyphInfo(
          gid: font.glyphForRune(u.codepoint) ?? 0,
          cluster: u.cluster,
          text: List<int>.of(u.sourceText),
          mask: _F.global,
        ),
      );
    }

    _applyFeature('ccmp', _F.ccmp, buf);
    _applyFeature('locl', _F.locl, buf);

    final positions = List<int>.filled(buf.length, IndicPosition.baseConsonant);
    final codepoints = <int>[for (final u in units) u.codepoint];
    final categories = <IndicCategory>[
      for (final u in units) categoryOf(u.codepoint),
    ];
    final ranges = _syllables(categories);
    for (var sy = 0; sy < ranges.length; sy++) {
      _initialReorder(
        buf,
        codepoints,
        categories,
        positions,
        ranges[sy].$1,
        ranges[sy].$2,
        sy,
      );
    }

    for (final (tag, mask) in _basicFeatures) {
      _applyFeature(tag, mask, buf);
    }

    _finalReorder(buf);

    for (final (tag, mask) in _presentationFeatures) {
      _applyFeature(tag, mask, buf);
    }
    for (final (tag, mask) in _finalFeatures) {
      _applyFeature(tag, mask, buf);
    }

    for (final g in buf) {
      g.xAdvance = font.advance(g.gid);
    }
    _gpos?.apply(buf, _gposFeatures);

    _dropDefaultIgnorables(buf);

    return ShapedRun(
      glyphs: buf,
      source: text,
      unitsPerEm: font.unitsPerEm,
      clusters: _clusters(buf, units, ranges, text),
    );
  }

  /// Prefixes a dotted circle to any syllable that starts with a mark.
  List<_Unit> _insertDottedCircles(List<_Unit> units) {
    final dotted = font.glyphForRune(kDottedCircle);
    if (dotted == null) return units;
    final categories = <IndicCategory>[
      for (final u in units) categoryOf(u.codepoint),
    ];
    final broken = <int>{};
    for (final (start, _) in _syllables(categories)) {
      switch (categories[start]) {
        case IndicCategory.matra:
        case IndicCategory.halant:
        case IndicCategory.nukta:
        case IndicCategory.syllableModifier:
          broken.add(start);
        case _:
          break;
      }
    }
    if (broken.isEmpty) return units;
    final out = <_Unit>[];
    for (var i = 0; i < units.length; i++) {
      if (broken.contains(i)) {
        out.add(_Unit(kDottedCircle, units[i].cluster, const <int>[], 0));
      }
      out.add(units[i]);
    }
    return out;
  }

  /// Removes ZWJ and ZWNJ from the output. They have done their shaping work
  /// by this point and must not reach the PDF as glyphs.
  void _dropDefaultIgnorables(List<GlyphInfo> buf) {
    for (var i = buf.length - 1; i >= 0; i--) {
      final text = buf[i].text;
      final isJoiner =
          text.length == 1 && (text.first == kZwj || text.first == kZwnj);
      if (!isJoiner) continue;
      buf.removeAt(i);
    }
  }

  /// Groups the shaped glyphs into syllable clusters carrying their source
  /// substring, so the PDF writer can emit `/ActualText` per cluster.
  List<ShapedCluster> _clusters(
    List<GlyphInfo> buf,
    List<_Unit> units,
    List<(int, int)> ranges,
    String text,
  ) {
    if (buf.isEmpty) return const <ShapedCluster>[];
    // Source code-unit span of each syllable.
    final spans = <int, (int, int)>{};
    for (var sy = 0; sy < ranges.length; sy++) {
      final (start, end) = ranges[sy];
      var from = text.length;
      var to = 0;
      for (var i = start; i < end && i < units.length; i++) {
        final unit = units[i];
        if (unit.cluster < from) from = unit.cluster;
        final unitEnd = unit.cluster + unit.length;
        if (unitEnd > to) to = unitEnd;
      }
      if (from >= to) continue;
      spans[sy] = (from, to);
    }

    final out = <ShapedCluster>[];
    var i = 0;
    while (i < buf.length) {
      final sy = buf[i].syllable;
      var end = i;
      while (end < buf.length && buf[end].syllable == sy) {
        end++;
      }
      final span = spans[sy];
      out.add(
        ShapedCluster(
          text: span == null
              ? ''
              : text.substring(
                  span.$1.clamp(0, text.length),
                  span.$2.clamp(0, text.length),
                ),
          glyphStart: i,
          glyphEnd: end,
        ),
      );
      i = end;
    }
    return out;
  }

  /// Set `BANGLA_PDF_TRACE=1` to dump the buffer after every lookup. Dev only.
  static final bool _trace = Platform.environment['BANGLA_PDF_TRACE'] == '1';

  void _applyFeature(String tag, int mask, List<GlyphInfo> buf) {
    final lookups = _gsubFeatures[tag];
    if (lookups == null || _gsub == null) return;
    for (final index in lookups) {
      final before = _trace ? buf.map((g) => g.gid).toList() : null;
      _gsub.applyLookup(buf, index, mask);
      if (_trace) {
        final after = buf.map((g) => g.gid).toList();
        if ('$before' != '$after') {
          // ignore: avoid_print
          print('    $tag lookup $index: $before -> $after');
        }
      }
    }
  }

  // --- normalisation --------------------------------------------------------

  /// One codepoint after normalisation, with the source text it stands for.
  ///
  /// [cluster] is the index of the first source code unit, so glyphs can be
  /// grouped back into the original grapheme for `/ActualText`.
  List<_Unit> _normalise(String text) {
    final out = <_Unit>[];
    final runes = text.runes.toList();

    // Track the source code-unit offset of each rune so clusters map back to
    // substring ranges of the original string.
    final offsets = <int>[];
    var offset = 0;
    for (final r in runes) {
      offsets.add(offset);
      offset += r > 0xFFFF ? 2 : 1;
    }

    for (var i = 0; i < runes.length; i++) {
      final cp = runes[i];
      final at = offsets[i];

      // Consonant + nukta -> precomposed, so NFD and NFC shape identically.
      final width = cp > 0xFFFF ? 2 : 1;

      final composed = kNuktaComposition[cp];
      if (composed != null && i + 1 < runes.length && runes[i + 1] == kNukta) {
        out.add(_Unit(composed, at, <int>[cp, kNukta], width + 1));
        i++;
        continue;
      }

      // Two-part vowel signs are decomposed: fonts' rules target the parts.
      final parts = kMatraDecomposition[cp];
      if (parts != null) {
        out
          ..add(_Unit(parts[0], at, <int>[cp], width))
          ..add(_Unit(parts[1], at, const <int>[], 0));
        continue;
      }

      out.add(_Unit(cp, at, <int>[cp], width));
    }
    return out;
  }

  // --- syllables ------------------------------------------------------------

  /// Splits the buffer into `[start, end)` syllable ranges.
  ///
  /// A consonant syllable is
  /// `(C N? (H ZW?)?)* (C|V) N? (H ZW?)? M* SM*`, approximated by starting a
  /// new syllable at any base-eligible character that is not bound to the
  /// previous one by a halant or joiner.
  List<(int, int)> _syllables(List<IndicCategory> cat) {
    final result = <(int, int)>[];
    var start = 0;
    var i = 0;
    while (i < cat.length) {
      final c = cat[i];
      final startsNew = i > start &&
          (isConsonantCategory(c) || c == IndicCategory.vowel) &&
          !_boundToPrevious(cat, i);
      if (startsNew) {
        result.add((start, i));
        start = i;
      }
      if (!isConsonantCategory(c) &&
          c != IndicCategory.vowel &&
          c != IndicCategory.matra &&
          c != IndicCategory.syllableModifier &&
          c != IndicCategory.nukta &&
          c != IndicCategory.halant &&
          c != IndicCategory.zwj &&
          c != IndicCategory.zwnj) {
        // Non-Indic character: it is its own syllable.
        if (i > start) result.add((start, i));
        result.add((i, i + 1));
        start = i + 1;
      }
      i++;
    }
    if (start < cat.length) result.add((start, cat.length));
    return result;
  }

  /// Whether the character at [i] continues the previous syllable, i.e. it is
  /// preceded by a halant (optionally with a joiner in between).
  bool _boundToPrevious(List<IndicCategory> cat, int i) {
    var j = i - 1;
    if (j >= 0 &&
        (cat[j] == IndicCategory.zwj || cat[j] == IndicCategory.zwnj)) {
      j--;
    }
    return j >= 0 && cat[j] == IndicCategory.halant;
  }

  // --- initial reordering ---------------------------------------------------

  void _initialReorder(
    List<GlyphInfo> buf,
    List<int> cps,
    List<IndicCategory> cat,
    List<int> pos,
    int start,
    int end,
    int syllableIndex,
  ) {
    if (end - start <= 0 || end > buf.length) return;

    // 1. Provisional positions from the normalised character itself.
    for (var i = start; i < end; i++) {
      pos[i] = defaultPositionOf(cps[i]);
    }

    // 2. Refine consonant positions using the font: a consonant the font gives
    //    a below-base or post-base form to cannot be the base.
    for (var i = start; i < end; i++) {
      if (isConsonantCategory(cat[i]) &&
          pos[i] == IndicPosition.baseConsonant) {
        pos[i] = _consonantPosition(buf[i].gid);
      }
    }

    // 3. Reph: an initial RA followed by a halant, when the syllable has more
    //    consonants after it.
    var limit = start;
    final hasReph = _hasReph(buf, cat, start, end);
    if (hasReph) {
      buf[start].mask |= _F.rphf;
      buf[start + 1].mask |= _F.rphf;
      limit = start + 2;
    }

    // 4. Find the base consonant, scanning backwards (Bengali is BASE_POS_LAST).
    var base = end;
    var seenBelow = false;
    var i = end;
    while (i > limit) {
      i--;
      if (isConsonantCategory(cat[i])) {
        if (pos[i] != IndicPosition.belowConsonant &&
            (pos[i] != IndicPosition.postConsonant || seenBelow)) {
          base = i;
          break;
        }
        if (pos[i] == IndicPosition.belowConsonant) seenBelow = true;
        base = i;
      } else if (cat[i] == IndicCategory.zwj &&
          i > start &&
          cat[i - 1] == IndicCategory.halant) {
        // An explicit half form was requested; stop searching.
        break;
      }
    }
    if (base >= end) {
      // No consonant (a vowel or standalone syllable): nothing to reorder
      // beyond matra placement.
      base = limit < end ? limit : end - 1;
    }

    // 5. Everything before the base is a pre-base form; the base is the base.
    for (var k = limit; k < base; k++) {
      if (pos[k] > IndicPosition.preConsonant) {
        pos[k] = IndicPosition.preConsonant;
      }
    }
    if (base < end) pos[base] = IndicPosition.baseConsonant;
    if (hasReph) {
      pos[start] = IndicPosition.raToBecomeReph;
      pos[start + 1] = IndicPosition.raToBecomeReph;
    }

    // 6. Halants, joiners and nuktas take the position of the character they
    //    follow, so they travel with it rather than being sorted away from it.
    var lastPos = IndicPosition.start;
    for (var k = start; k < end; k++) {
      final c = cat[k];
      if (c == IndicCategory.halant ||
          c == IndicCategory.zwj ||
          c == IndicCategory.zwnj ||
          c == IndicCategory.nukta) {
        pos[k] = lastPos;
        if (c == IndicCategory.halant && pos[k] == IndicPosition.preMatra) {
          // A halant never travels with a pre-base matra; give it the position
          // of the nearest earlier character that is not one.
          for (var j = k; j > start; j--) {
            if (pos[j - 1] != IndicPosition.preMatra) {
              pos[k] = pos[j - 1];
              break;
            }
          }
        }
      } else if (pos[k] != IndicPosition.smvd) {
        lastPos = pos[k];
      }
    }

    // 7. A post-base consonant owns everything between it and the previous
    //    consonant or matra, which keeps its halant attached to it.
    var last = base;
    for (var k = base + 1; k < end; k++) {
      if (isConsonantCategory(cat[k])) {
        for (var j = last + 1; j < k; j++) {
          if (pos[j] < IndicPosition.smvd) pos[j] = pos[k];
        }
        last = k;
      } else if (cat[k] == IndicCategory.matra) {
        last = k;
      }
    }

    // 8. Masks, per the Indic model: half and blwf before the base (Bengali
    //    applies blwf both sides), blwf/abvf/pstf after it.
    for (var k = limit; k < base; k++) {
      buf[k].mask |= _F.half | _F.blwf;
    }
    for (var k = base + 1; k < end; k++) {
      buf[k].mask |= _F.blwf | _F.abvf | _F.pstf;
    }

    // 9. Record positions and the syllable id so final reordering can still
    //    work after GSUB has merged glyphs.
    for (var k = start; k < end; k++) {
      buf[k].position = pos[k];
      buf[k].syllable = syllableIndex;
    }

    // 10. Stable-sort the syllable by position. This is what moves ি ে ৈ in
    //     front of their cluster.
    _stableSortSyllable(buf, cps, cat, pos, start, end);

    // 11. A pre-base matra that begins a word takes the `init` form, which is
    //     how fonts give ে / ৈ their word-initial shape. A leading reph sorts
    //     ahead of the matra but does not stop the matra being word-initial.
    if (_isWordStart(cat, start)) {
      for (var k = start; k < end; k++) {
        if (pos[k] == IndicPosition.preMatra) {
          buf[k].mask |= _F.init;
          break;
        }
        if (pos[k] != IndicPosition.raToBecomeReph) break;
      }
    }
  }

  /// Whether the syllable at [start] begins a word, i.e. it is not preceded by
  /// another letter or mark.
  bool _isWordStart(List<IndicCategory> cat, int start) {
    if (start == 0) return true;
    final previous = cat[start - 1];
    return previous != IndicCategory.consonant &&
        previous != IndicCategory.ra &&
        previous != IndicCategory.vowel &&
        previous != IndicCategory.matra &&
        previous != IndicCategory.nukta &&
        previous != IndicCategory.halant &&
        previous != IndicCategory.syllableModifier &&
        previous != IndicCategory.placeholder;
  }

  bool _hasReph(
    List<GlyphInfo> buf,
    List<IndicCategory> cat,
    int start,
    int end,
  ) {
    if (_gsubFeatures['rphf'] == null) return false;
    if (end - start < 3) return false;
    if (cat[start] != IndicCategory.ra) return false;
    if (cat[start + 1] != IndicCategory.halant) return false;
    // ZWJ after the halant explicitly requests the ra-phala, not a reph.
    if (start + 2 < end && cat[start + 2] == IndicCategory.zwj) return false;
    // There must be something for the reph to sit on.
    var sawConsonant = false;
    for (var i = start + 2; i < end; i++) {
      if (isConsonantCategory(cat[i]) || cat[i] == IndicCategory.vowel) {
        sawConsonant = true;
        break;
      }
    }
    return sawConsonant;
  }

  void _stableSortSyllable(
    List<GlyphInfo> buf,
    List<int> cps,
    List<IndicCategory> cat,
    List<int> pos,
    int start,
    int end,
  ) {
    final indices = <int>[for (var i = start; i < end; i++) i];
    // Stable insertion sort keyed on position.
    for (var a = 1; a < indices.length; a++) {
      final key = indices[a];
      var b = a - 1;
      while (b >= 0 && pos[indices[b]] > pos[key]) {
        indices[b + 1] = indices[b];
        b--;
      }
      indices[b + 1] = key;
    }
    final glyphs = <GlyphInfo>[for (final i in indices) buf[i]];
    final cats = <IndicCategory>[for (final i in indices) cat[i]];
    final ps = <int>[for (final i in indices) pos[i]];
    final cs = <int>[for (final i in indices) cps[i]];
    for (var i = 0; i < indices.length; i++) {
      buf[start + i] = glyphs[i];
      cat[start + i] = cats[i];
      pos[start + i] = ps[i];
      cps[start + i] = cs[i];
    }
  }

  // --- final reordering -----------------------------------------------------

  /// Moves the reph glyph to its Bengali position.
  ///
  /// Bengali uses `REPH_POS_AFTER_SUBSCRIPT`: the reph sits after the base and
  /// any below-base form, but before post-base forms and syllable modifiers.
  void _finalReorder(List<GlyphInfo> buf) {
    var i = 0;
    while (i < buf.length) {
      final syllable = buf[i].syllable;
      var end = i;
      while (end < buf.length && buf[end].syllable == syllable) {
        end++;
      }
      _finalReorderSyllable(buf, i, end);
      i = end;
    }
  }

  void _finalReorderSyllable(List<GlyphInfo> buf, int start, int end) {
    if (end - start < 2) return;

    // The reph survives as a single glyph only if rphf actually substituted
    // the RA + halant pair. If both are still present, there is no reph.
    if (buf[start].position != IndicPosition.raToBecomeReph) return;
    if (buf[start + 1].position == IndicPosition.raToBecomeReph) return;

    // Find the base: the first glyph at or past the base position. GSUB may
    // have ligated the base away into a pre-base form, in which case fall back
    // to the first glyph after the reph that is not a pre-base matra.
    var base = start;
    while (base < end &&
        (buf[base].position < IndicPosition.baseConsonant ||
            buf[base].position >= IndicPosition.postConsonant)) {
      base++;
    }
    if (base >= end) {
      base = start + 1;
      while (base < end && buf[base].position == IndicPosition.preMatra) {
        base++;
      }
      if (base >= end) return;
    }

    // Walk forward over below-base material, stopping before post-base forms
    // and syllable modifiers.
    var target = base;
    while (target + 1 < end) {
      final next = buf[target + 1].position;
      if (next == IndicPosition.postConsonant ||
          next == IndicPosition.afterPost ||
          next == IndicPosition.smvd) {
        break;
      }
      target++;
    }
    if (target <= start) return;

    final reph = buf.removeAt(start);
    reph.reordered = true;
    buf.insert(target, reph);
  }

  // --- font queries ---------------------------------------------------------

  int get _virama => _viramaGlyph ??= font.glyphForRune(kVirama) ?? 0;

  /// Whether the font gives [glyph] a below-base or post-base form, which
  /// disqualifies it from being the base consonant.
  int _consonantPosition(int glyph) {
    final cached = _consonantPositionCache[glyph];
    if (cached != null) return cached;
    var result = IndicPosition.baseConsonant;
    final virama = _virama;
    if (virama != 0) {
      if (_wouldSubstitute('blwf', <int>[virama, glyph]) ||
          _wouldSubstitute('blwf', <int>[glyph, virama])) {
        result = IndicPosition.belowConsonant;
      } else if (_wouldSubstitute('pstf', <int>[virama, glyph]) ||
          _wouldSubstitute('pstf', <int>[glyph, virama])) {
        result = IndicPosition.postConsonant;
      }
    }
    _consonantPositionCache[glyph] = result;
    return result;
  }

  /// Whether any lookup of [tag] would apply to the exact sequence [glyphs].
  bool _wouldSubstitute(String tag, List<int> glyphs) {
    final lookups = _gsubFeatures[tag];
    final gsub = _gsub;
    if (lookups == null || gsub == null) return false;
    for (final index in lookups) {
      if (gsub.wouldApply(glyphs, index)) return true;
    }
    return false;
  }
}

class _Unit {
  const _Unit(this.codepoint, this.cluster, this.sourceText, this.length);

  /// The (possibly normalised) codepoint to look up in the font.
  final int codepoint;

  /// Offset of the first source code unit this came from.
  final int cluster;

  /// Original codepoints, for `/ToUnicode`.
  final List<int> sourceText;

  /// How many source code units this unit consumed. A composed nukta pair
  /// covers two, so the cluster's source substring must extend that far.
  final int length;
}
