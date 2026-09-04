/// The shaping buffer: glyphs plus the source text each one stands for.
///
/// Tracking source codepoints per glyph is what lets us emit a `/ToUnicode`
/// CMap in which a ligature such as ক্ষ্ম maps back to its full five-codepoint
/// sequence, so copy/paste out of the PDF yields the original Unicode.
library;

import 'package:bangla_pdf/src/ot/ot_font.dart';

/// One glyph in the shaping buffer.
class GlyphInfo {
  GlyphInfo({
    required this.gid,
    required this.cluster,
    required this.text,
    this.mask = 0,
  });

  /// Glyph id in the font.
  int gid;

  /// Index of the first source code unit this glyph derives from. Glyphs that
  /// belong to the same indivisible unit share a cluster value.
  int cluster;

  /// The source codepoints this glyph represents, in logical order.
  ///
  /// Empty when an earlier glyph in the same cluster already carries the text
  /// (for example the trailing halves of a one-to-many substitution).
  List<int> text;

  /// Feature mask: which features may apply to this glyph.
  int mask;

  /// Set for glyphs the Indic shaper has moved out of logical order.
  bool reordered = false;

  /// Position within the syllable, from `IndicPosition`. Survives GSUB so that
  /// final reordering can place the reph after substitutions have run.
  int position = 0;

  /// Index of the syllable this glyph belongs to.
  int syllable = 0;

  // --- positioning, filled in by GPOS ---

  /// Horizontal advance in font units.
  int xAdvance = 0;

  /// Vertical advance in font units.
  int yAdvance = 0;

  /// Horizontal placement offset in font units.
  int xOffset = 0;

  /// Vertical placement offset in font units.
  int yOffset = 0;

  /// Index of the glyph this one is attached to, relative to itself, or 0.
  int attachChain = 0;

  /// Non-zero when this glyph is a mark attached via GPOS.
  bool isAttached = false;

  GlyphInfo copy() => GlyphInfo(
        gid: gid,
        cluster: cluster,
        text: List<int>.of(text),
        mask: mask,
      )
        ..reordered = reordered
        ..position = position
        ..syllable = syllable
        ..xAdvance = xAdvance
        ..yAdvance = yAdvance
        ..xOffset = xOffset
        ..yOffset = yOffset;

  @override
  String toString() => 'g$gid@$cluster';
}

/// Lookup flag bits shared by GSUB and GPOS.
class LookupFlag {
  static const int rightToLeft = 0x0001;
  static const int ignoreBaseGlyphs = 0x0002;
  static const int ignoreLigatures = 0x0004;
  static const int ignoreMarks = 0x0008;
  static const int useMarkFilteringSet = 0x0010;
  static const int markAttachmentType = 0xFF00;
}

/// Decides whether a glyph is skipped while matching a lookup's sequence.
class SkipFilter {
  SkipFilter(
    this.font,
    this.flags, [
    this.markFilteringSet = -1,
    this.syllable = -1,
    this.mask = 0,
  ]);

  final OtFont font;
  final int flags;

  /// Feature mask being applied, or 0 for no mask filtering.
  ///
  /// A glyph the current feature is not allowed to touch *ends* the match — it
  /// is not stepped over. This is what stops `half` from consuming the halant
  /// of a following ya-phala: that halant carries the `pstf` mask, not `half`,
  /// so the `half` lookup simply does not match there.
  final int mask;

  /// When non-negative, matching stops at a syllable boundary.
  ///
  /// The OpenType Indic model applies its features per syllable, so a lookup
  /// must never match a sequence spanning two syllables. Without this, a
  /// contextual rule written for "matra ... reph" fires across a word like
  /// নির্মাণ where the matra and the reph belong to different syllables.
  final int syllable;

  /// Index of the `GDEF` mark glyph set to honour, or -1 when the lookup does
  /// not use one.
  final int markFilteringSet;

  /// Whether [g] should be stepped over when matching.
  bool skip(GlyphInfo g) {
    final cls = font.glyphClass(g.gid);
    if (flags & LookupFlag.ignoreMarks != 0 && cls == GlyphClass.mark) {
      return true;
    }
    if (flags & LookupFlag.ignoreBaseGlyphs != 0 && cls == GlyphClass.base) {
      return true;
    }
    if (flags & LookupFlag.ignoreLigatures != 0 && cls == GlyphClass.ligature) {
      return true;
    }
    if (cls == GlyphClass.mark) {
      // A mark filtering set narrows matching to the marks it lists; every
      // other mark is stepped over.
      if (flags & LookupFlag.useMarkFilteringSet != 0 &&
          markFilteringSet >= 0) {
        final set = font.markGlyphSet(markFilteringSet);
        if (set != null && !set.covers(g.gid)) return true;
      }
      final attachType = (flags & LookupFlag.markAttachmentType) >> 8;
      if (attachType != 0 && font.markAttachClass(g.gid) != attachType) {
        return true;
      }
    }
    return false;
  }

  /// Whether [g] is a glyph the current feature may match at all.
  bool _matchable(GlyphInfo g) => mask == 0 || g.mask & mask != 0;

  /// Index of the next non-skipped glyph strictly after [from], or `null`.
  int? next(List<GlyphInfo> buf, int from) {
    for (var i = from + 1; i < buf.length; i++) {
      if (syllable >= 0 && buf[i].syllable != syllable) return null;
      if (skip(buf[i])) continue;
      return _matchable(buf[i]) ? i : null;
    }
    return null;
  }

  /// Index of the previous non-skipped glyph strictly before [from], or `null`.
  int? previous(List<GlyphInfo> buf, int from) {
    for (var i = from - 1; i >= 0; i--) {
      if (syllable >= 0 && buf[i].syllable != syllable) return null;
      if (skip(buf[i])) continue;
      return _matchable(buf[i]) ? i : null;
    }
    return null;
  }

  /// Walks forward from [start] collecting [count] non-skipped positions.
  ///
  /// Returns `null` if the buffer runs out. The returned list does not include
  /// [start] itself.
  List<int>? forward(List<GlyphInfo> buf, int start, int count) {
    if (count == 0) return const <int>[];
    final out = <int>[];
    var i = start;
    while (out.length < count) {
      final n = next(buf, i);
      if (n == null) return null;
      out.add(n);
      i = n;
    }
    return out;
  }

  /// Walks backward from [start] collecting [count] non-skipped positions.
  List<int>? backward(List<GlyphInfo> buf, int start, int count) {
    if (count == 0) return const <int>[];
    final out = <int>[];
    var i = start;
    while (out.length < count) {
      final p = previous(buf, i);
      if (p == null) return null;
      out.add(p);
      i = p;
    }
    return out;
  }
}
