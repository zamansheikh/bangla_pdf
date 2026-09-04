/// GSUB glyph substitution.
///
/// Implements lookup types 1 (single), 2 (multiple), 3 (alternate), 4
/// (ligature), 5 (context), 6 (chained context) and 7 (extension). Types 5–7
/// recurse into other lookups, which is how Indic fonts express `cjct`,
/// `half`, `pstf` and `pres`.
///
/// Type 8 (reverse chained single) is not implemented; no Bengali font in the
/// test corpus uses it, and an unimplemented type is skipped rather than
/// mis-applied.
library;

import 'package:bangla_pdf/src/ot/glyph_buffer.dart';
import 'package:bangla_pdf/src/ot/ot_font.dart';
import 'package:bangla_pdf/src/ot/ot_reader.dart';

/// Applies GSUB lookups to a glyph buffer.
class GsubEngine {
  GsubEngine(this.font, this.table) : d = font.d;

  final OtFont font;
  final LayoutTable table;
  final OtData d;

  /// Guards against pathological or malicious fonts with cyclic lookups.
  static const int _maxRecursionDepth = 8;
  int _depth = 0;

  /// Applies lookup [lookupIndex] across [buf], to glyphs matching [mask].
  ///
  /// A [mask] of 0 means "no mask filtering" and is used for nested lookups.
  void applyLookup(List<GlyphInfo> buf, int lookupIndex, int mask) {
    final lookup = table.lookupOffset(lookupIndex);
    if (lookup == null) return;
    final type = d.u16(lookup);
    final flags = d.u16(lookup + 2);

    var i = 0;
    var guard = 0;
    final maxSteps = buf.length * 64 + 1024;
    while (i < buf.length) {
      if (++guard > maxSteps) break;
      if (mask != 0 && buf[i].mask & mask == 0) {
        i++;
        continue;
      }
      final advance = _applyAt(buf, i, lookup, type, flags);
      i += (advance == null || advance <= 0) ? 1 : advance;
    }
  }

  /// Whether lookup [lookupIndex] would apply to the exact glyph sequence
  /// [glyphs], ignoring surrounding context.
  ///
  /// This mirrors HarfBuzz's `would_apply`: contextual lookups are tested
  /// against their *input* sequence only, with backtrack and lookahead
  /// disregarded. The Indic shaper uses it to ask a font "do you give this
  /// consonant a below-base or post-base form?", which has no real context.
  bool wouldApply(List<int> glyphs, int lookupIndex) {
    final lookup = table.lookupOffset(lookupIndex);
    if (lookup == null || glyphs.isEmpty) return false;
    final type = d.u16(lookup);
    final subtableCount = d.u16(lookup + 4);
    for (var s = 0; s < subtableCount; s++) {
      var sub = lookup + d.u16(lookup + 6 + 2 * s);
      var effectiveType = type;
      if (type == 7) {
        if (d.u16(sub) != 1) continue;
        effectiveType = d.u16(sub + 2);
        sub = sub + d.u32(sub + 4);
      }
      if (_wouldApplySubtable(glyphs, sub, effectiveType)) return true;
    }
    return false;
  }

  bool _wouldApplySubtable(List<int> glyphs, int sub, int type) {
    switch (type) {
      case 1:
      case 2:
      case 3:
        if (glyphs.length != 1) return false;
        return Coverage.parse(d, sub + d.u16(sub + 2)).covers(glyphs[0]);

      case 4:
        if (d.u16(sub) != 1) return false;
        final coverage = Coverage.parse(d, sub + d.u16(sub + 2));
        final index = coverage.indexOf(glyphs[0]);
        if (index == null || index >= d.u16(sub + 4)) return false;
        final set = sub + d.u16(sub + 6 + 2 * index);
        final ligCount = d.u16(set);
        for (var l = 0; l < ligCount; l++) {
          final lig = set + d.u16(set + 2 + 2 * l);
          final compCount = d.u16(lig + 2);
          if (compCount != glyphs.length) continue;
          var ok = true;
          for (var c = 1; c < compCount; c++) {
            if (glyphs[c] != d.u16(lig + 4 + 2 * (c - 1))) {
              ok = false;
              break;
            }
          }
          if (ok) return true;
        }
        return false;

      case 5:
        return _wouldApplyContext(glyphs, sub);

      case 6:
        return _wouldApplyChainContext(glyphs, sub);

      default:
        return false;
    }
  }

  bool _wouldApplyContext(List<int> glyphs, int sub) {
    switch (d.u16(sub)) {
      case 1:
        final coverage = Coverage.parse(d, sub + d.u16(sub + 2));
        final index = coverage.indexOf(glyphs[0]);
        if (index == null || index >= d.u16(sub + 4)) return false;
        final set = sub + d.u16(sub + 6 + 2 * index);
        final ruleCount = d.u16(set);
        for (var r = 0; r < ruleCount; r++) {
          final rule = set + d.u16(set + 2 + 2 * r);
          final glyphCount = d.u16(rule);
          if (glyphCount != glyphs.length) continue;
          var ok = true;
          for (var c = 1; c < glyphCount; c++) {
            if (glyphs[c] != d.u16(rule + 4 + 2 * (c - 1))) {
              ok = false;
              break;
            }
          }
          if (ok) return true;
        }
        return false;

      case 2:
        final coverage = Coverage.parse(d, sub + d.u16(sub + 2));
        if (!coverage.covers(glyphs[0])) return false;
        final classDef = ClassDef.parse(d, sub + d.u16(sub + 4));
        final setCount = d.u16(sub + 6);
        final startClass = classDef.of(glyphs[0]);
        if (startClass >= setCount) return false;
        final setOffset = d.u16(sub + 8 + 2 * startClass);
        if (setOffset == 0) return false;
        final set = sub + setOffset;
        final ruleCount = d.u16(set);
        for (var r = 0; r < ruleCount; r++) {
          final rule = set + d.u16(set + 2 + 2 * r);
          final glyphCount = d.u16(rule);
          if (glyphCount != glyphs.length) continue;
          var ok = true;
          for (var c = 1; c < glyphCount; c++) {
            if (classDef.of(glyphs[c]) != d.u16(rule + 4 + 2 * (c - 1))) {
              ok = false;
              break;
            }
          }
          if (ok) return true;
        }
        return false;

      case 3:
        final glyphCount = d.u16(sub + 2);
        if (glyphCount != glyphs.length) return false;
        for (var c = 0; c < glyphCount; c++) {
          if (!Coverage.parse(d, sub + d.u16(sub + 6 + 2 * c))
              .covers(glyphs[c])) {
            return false;
          }
        }
        return true;

      default:
        return false;
    }
  }

  bool _wouldApplyChainContext(List<int> glyphs, int sub) {
    switch (d.u16(sub)) {
      case 1:
        final coverage = Coverage.parse(d, sub + d.u16(sub + 2));
        final index = coverage.indexOf(glyphs[0]);
        if (index == null || index >= d.u16(sub + 4)) return false;
        final set = sub + d.u16(sub + 6 + 2 * index);
        final ruleCount = d.u16(set);
        for (var r = 0; r < ruleCount; r++) {
          var o = set + d.u16(set + 2 + 2 * r);
          o += 2 + 2 * d.u16(o); // skip backtrack
          final inputCount = d.u16(o);
          if (inputCount != glyphs.length) continue;
          var ok = true;
          for (var c = 1; c < inputCount; c++) {
            if (glyphs[c] != d.u16(o + 2 + 2 * (c - 1))) {
              ok = false;
              break;
            }
          }
          if (ok) return true;
        }
        return false;

      case 2:
        final coverage = Coverage.parse(d, sub + d.u16(sub + 2));
        if (!coverage.covers(glyphs[0])) return false;
        final inputClass = ClassDef.parse(d, sub + d.u16(sub + 6));
        final setCount = d.u16(sub + 10);
        final startClass = inputClass.of(glyphs[0]);
        if (startClass >= setCount) return false;
        final setOffset = d.u16(sub + 12 + 2 * startClass);
        if (setOffset == 0) return false;
        final set = sub + setOffset;
        final ruleCount = d.u16(set);
        for (var r = 0; r < ruleCount; r++) {
          var o = set + d.u16(set + 2 + 2 * r);
          o += 2 + 2 * d.u16(o); // skip backtrack
          final inputCount = d.u16(o);
          if (inputCount != glyphs.length) continue;
          var ok = true;
          for (var c = 1; c < inputCount; c++) {
            if (inputClass.of(glyphs[c]) != d.u16(o + 2 + 2 * (c - 1))) {
              ok = false;
              break;
            }
          }
          if (ok) return true;
        }
        return false;

      case 3:
        var o = sub + 2;
        o += 2 + 2 * d.u16(o); // skip backtrack coverages
        final inputCount = d.u16(o);
        if (inputCount != glyphs.length) return false;
        for (var c = 0; c < inputCount; c++) {
          if (!Coverage.parse(d, sub + d.u16(o + 2 + 2 * c))
              .covers(glyphs[c])) {
            return false;
          }
        }
        return true;

      default:
        return false;
    }
  }

  /// Applies a whole lookup once at [pos], for nested SubstLookupRecords.
  ///
  /// Returns true when a substitution happened.
  bool _applyLookupAt(List<GlyphInfo> buf, int pos, int lookupIndex) {
    if (_depth >= _maxRecursionDepth) return false;
    final lookup = table.lookupOffset(lookupIndex);
    if (lookup == null || pos < 0 || pos >= buf.length) return false;
    _depth++;
    try {
      final type = d.u16(lookup);
      final flags = d.u16(lookup + 2);
      return _applyAt(buf, pos, lookup, type, flags) != null;
    } finally {
      _depth--;
    }
  }

  /// Tries every subtable of the lookup at [lookup] against [pos].
  ///
  /// Returns how far the cursor should advance, or `null` when nothing matched.
  int? _applyAt(
    List<GlyphInfo> buf,
    int pos,
    int lookup,
    int type,
    int flags,
  ) {
    final subtableCount = d.u16(lookup + 4);
    // The mark filtering set index follows the subtable offset array.
    final markFilteringSet = flags & LookupFlag.useMarkFilteringSet != 0
        ? d.u16(lookup + 6 + 2 * subtableCount)
        : -1;
    for (var s = 0; s < subtableCount; s++) {
      var subtable = lookup + d.u16(lookup + 6 + 2 * s);
      var effectiveType = type;
      if (type == 7) {
        // Extension: redirect to the real type and offset.
        if (d.u16(subtable) != 1) continue;
        effectiveType = d.u16(subtable + 2);
        subtable = subtable + d.u32(subtable + 4);
      }
      final r = _applySubtable(
        buf,
        pos,
        subtable,
        effectiveType,
        flags,
        markFilteringSet,
      );
      if (r != null) return r;
    }
    return null;
  }

  int? _applySubtable(
    List<GlyphInfo> buf,
    int pos,
    int sub,
    int type,
    int flags,
    int markFilteringSet,
  ) {
    switch (type) {
      case 1:
        return _single(buf, pos, sub);
      case 2:
        return _multiple(buf, pos, sub);
      case 3:
        return _alternate(buf, pos, sub);
      case 4:
        return _ligature(buf, pos, sub, flags, markFilteringSet);
      case 5:
        return _context(buf, pos, sub, flags, markFilteringSet);
      case 6:
        return _chainContext(buf, pos, sub, flags, markFilteringSet);
      default:
        return null;
    }
  }

  // --- Type 1: single substitution ------------------------------------------

  int? _single(List<GlyphInfo> buf, int pos, int sub) {
    final g = buf[pos];
    final format = d.u16(sub);
    final coverage = Coverage.parse(d, sub + d.u16(sub + 2));
    final index = coverage.indexOf(g.gid);
    if (index == null) return null;
    if (format == 1) {
      g.gid = (g.gid + d.i16(sub + 4)) & 0xFFFF;
      return 1;
    }
    if (format == 2) {
      if (index >= d.u16(sub + 4)) return null;
      g.gid = d.u16(sub + 6 + 2 * index);
      return 1;
    }
    return null;
  }

  // --- Type 2: multiple substitution (one glyph -> many) --------------------

  int? _multiple(List<GlyphInfo> buf, int pos, int sub) {
    if (d.u16(sub) != 1) return null;
    final g = buf[pos];
    final coverage = Coverage.parse(d, sub + d.u16(sub + 2));
    final index = coverage.indexOf(g.gid);
    if (index == null || index >= d.u16(sub + 4)) return null;
    final seq = sub + d.u16(sub + 6 + 2 * index);
    final count = d.u16(seq);
    if (count == 0) {
      // A zero-length sequence deletes the glyph. Preserve its text on the
      // neighbour so copy/paste does not lose characters.
      final carry = g.text;
      buf.removeAt(pos);
      if (carry.isNotEmpty) {
        if (pos < buf.length) {
          buf[pos].text = [...carry, ...buf[pos].text];
        } else if (pos > 0) {
          buf[pos - 1].text = [...buf[pos - 1].text, ...carry];
        }
      }
      return 0;
    }
    // The first output glyph keeps the source text; the rest are continuations.
    final replacements = <GlyphInfo>[];
    for (var i = 0; i < count; i++) {
      replacements.add(
        GlyphInfo(
          gid: d.u16(seq + 2 + 2 * i),
          cluster: g.cluster,
          text: i == 0 ? g.text : <int>[],
          mask: g.mask,
        )
          ..position = g.position
          ..syllable = g.syllable,
      );
    }
    buf.replaceRange(pos, pos + 1, replacements);
    return count;
  }

  // --- Type 3: alternate substitution ---------------------------------------

  int? _alternate(List<GlyphInfo> buf, int pos, int sub) {
    if (d.u16(sub) != 1) return null;
    final g = buf[pos];
    final coverage = Coverage.parse(d, sub + d.u16(sub + 2));
    final index = coverage.indexOf(g.gid);
    if (index == null || index >= d.u16(sub + 4)) return null;
    final set = sub + d.u16(sub + 6 + 2 * index);
    if (d.u16(set) == 0) return null;
    // No alternate selection UI: always take the first, matching default shaping.
    g.gid = d.u16(set + 2);
    return 1;
  }

  // --- Type 4: ligature substitution ----------------------------------------

  int? _ligature(
    List<GlyphInfo> buf,
    int pos,
    int sub,
    int flags,
    int markFilteringSet,
  ) {
    if (d.u16(sub) != 1) return null;
    final coverage = Coverage.parse(d, sub + d.u16(sub + 2));
    final index = coverage.indexOf(buf[pos].gid);
    if (index == null || index >= d.u16(sub + 4)) return null;

    final skipper =
        SkipFilter(font, flags, markFilteringSet, buf[pos].syllable);
    final set = sub + d.u16(sub + 6 + 2 * index);
    final ligCount = d.u16(set);

    for (var l = 0; l < ligCount; l++) {
      final lig = set + d.u16(set + 2 + 2 * l);
      final ligGlyph = d.u16(lig);
      final compCount = d.u16(lig + 2);
      if (compCount == 0) continue;
      final positions = skipper.forward(buf, pos, compCount - 1);
      if (positions == null) continue;

      var matched = true;
      for (var c = 0; c < compCount - 1; c++) {
        if (buf[positions[c]].gid != d.u16(lig + 4 + 2 * c)) {
          matched = false;
          break;
        }
      }
      if (!matched) continue;

      // Merge in logical order: the ligature carries every component's text.
      final all = <int>[...buf[pos].text];
      final consumed = <int>[pos, ...positions];
      for (var c = 1; c < consumed.length; c++) {
        all.addAll(buf[consumed[c]].text);
      }
      // Any skipped glyph caught between components (a mark, typically) stays,
      // so remove consumed positions from the end backwards.
      final head = buf[pos];
      for (var c = consumed.length - 1; c >= 1; c--) {
        buf.removeAt(consumed[c]);
      }
      buf[pos] = GlyphInfo(
        gid: ligGlyph,
        cluster: head.cluster,
        text: all,
        mask: head.mask,
      )
        ..position = head.position
        ..syllable = head.syllable;
      return 1;
    }
    return null;
  }

  // --- Types 5 and 6: contextual substitution -------------------------------

  /// Applies the SubstLookupRecords of a matched context.
  ///
  /// [inputPositions] are absolute buffer indices of the matched input
  /// sequence. They are rewritten as nested lookups change the buffer length.
  int _applyRecords(
    List<GlyphInfo> buf,
    List<int> inputPositions,
    int recordsOffset,
    int recordCount,
  ) {
    final positions = List<int>.of(inputPositions);
    for (var r = 0; r < recordCount; r++) {
      final o = recordsOffset + 4 * r;
      final sequenceIndex = d.u16(o);
      final lookupIndex = d.u16(o + 2);
      if (sequenceIndex >= positions.length) continue;
      final at = positions[sequenceIndex];
      final before = buf.length;
      _applyLookupAt(buf, at, lookupIndex);
      final delta = buf.length - before;
      if (delta != 0) {
        for (var k = sequenceIndex + 1; k < positions.length; k++) {
          positions[k] += delta;
        }
      }
    }
    // Advance past the whole matched input, clamped to the current buffer.
    final last = positions.isEmpty ? 0 : positions.last;
    final start = positions.isEmpty ? 0 : positions.first;
    final advance = last - start + 1;
    return advance <= 0 ? 1 : advance;
  }

  int? _context(
    List<GlyphInfo> buf,
    int pos,
    int sub,
    int flags,
    int markFilteringSet,
  ) {
    final format = d.u16(sub);
    final skipper =
        SkipFilter(font, flags, markFilteringSet, buf[pos].syllable);

    switch (format) {
      case 1:
        final coverage = Coverage.parse(d, sub + d.u16(sub + 2));
        final index = coverage.indexOf(buf[pos].gid);
        if (index == null || index >= d.u16(sub + 4)) return null;
        final set = sub + d.u16(sub + 6 + 2 * index);
        final ruleCount = d.u16(set);
        for (var r = 0; r < ruleCount; r++) {
          final rule = set + d.u16(set + 2 + 2 * r);
          final glyphCount = d.u16(rule);
          final recordCount = d.u16(rule + 2);
          if (glyphCount == 0) continue;
          final positions = skipper.forward(buf, pos, glyphCount - 1);
          if (positions == null) continue;
          var ok = true;
          for (var c = 0; c < glyphCount - 1; c++) {
            if (buf[positions[c]].gid != d.u16(rule + 4 + 2 * c)) {
              ok = false;
              break;
            }
          }
          if (!ok) continue;
          return _applyRecords(
            buf,
            [pos, ...positions],
            rule + 4 + 2 * (glyphCount - 1),
            recordCount,
          );
        }
        return null;

      case 2:
        final coverage = Coverage.parse(d, sub + d.u16(sub + 2));
        if (coverage.indexOf(buf[pos].gid) == null) return null;
        final classDef = ClassDef.parse(d, sub + d.u16(sub + 4));
        final setCount = d.u16(sub + 6);
        final startClass = classDef.of(buf[pos].gid);
        if (startClass >= setCount) return null;
        final setOffset = d.u16(sub + 8 + 2 * startClass);
        if (setOffset == 0) return null;
        final set = sub + setOffset;
        final ruleCount = d.u16(set);
        for (var r = 0; r < ruleCount; r++) {
          final rule = set + d.u16(set + 2 + 2 * r);
          final glyphCount = d.u16(rule);
          final recordCount = d.u16(rule + 2);
          if (glyphCount == 0) continue;
          final positions = skipper.forward(buf, pos, glyphCount - 1);
          if (positions == null) continue;
          var ok = true;
          for (var c = 0; c < glyphCount - 1; c++) {
            if (classDef.of(buf[positions[c]].gid) != d.u16(rule + 4 + 2 * c)) {
              ok = false;
              break;
            }
          }
          if (!ok) continue;
          return _applyRecords(
            buf,
            [pos, ...positions],
            rule + 4 + 2 * (glyphCount - 1),
            recordCount,
          );
        }
        return null;

      case 3:
        final glyphCount = d.u16(sub + 2);
        final recordCount = d.u16(sub + 4);
        if (glyphCount == 0) return null;
        final first = Coverage.parse(d, sub + d.u16(sub + 6));
        if (first.indexOf(buf[pos].gid) == null) return null;
        final positions = skipper.forward(buf, pos, glyphCount - 1);
        if (positions == null) return null;
        for (var c = 1; c < glyphCount; c++) {
          final cov = Coverage.parse(d, sub + d.u16(sub + 6 + 2 * c));
          if (cov.indexOf(buf[positions[c - 1]].gid) == null) return null;
        }
        return _applyRecords(
          buf,
          [pos, ...positions],
          sub + 6 + 2 * glyphCount,
          recordCount,
        );

      default:
        return null;
    }
  }

  int? _chainContext(
    List<GlyphInfo> buf,
    int pos,
    int sub,
    int flags,
    int markFilteringSet,
  ) {
    final format = d.u16(sub);
    final skipper =
        SkipFilter(font, flags, markFilteringSet, buf[pos].syllable);

    switch (format) {
      case 1:
        final coverage = Coverage.parse(d, sub + d.u16(sub + 2));
        final index = coverage.indexOf(buf[pos].gid);
        if (index == null || index >= d.u16(sub + 4)) return null;
        final set = sub + d.u16(sub + 6 + 2 * index);
        final ruleCount = d.u16(set);
        for (var r = 0; r < ruleCount; r++) {
          var o = set + d.u16(set + 2 + 2 * r);
          final backtrackCount = d.u16(o);
          final backtrack = <int>[
            for (var i = 0; i < backtrackCount; i++) d.u16(o + 2 + 2 * i),
          ];
          o += 2 + 2 * backtrackCount;
          final inputCount = d.u16(o);
          if (inputCount == 0) continue;
          final input = <int>[
            for (var i = 0; i < inputCount - 1; i++) d.u16(o + 2 + 2 * i),
          ];
          o += 2 + 2 * (inputCount - 1);
          final lookaheadCount = d.u16(o);
          final lookahead = <int>[
            for (var i = 0; i < lookaheadCount; i++) d.u16(o + 2 + 2 * i),
          ];
          o += 2 + 2 * lookaheadCount;
          final recordCount = d.u16(o);
          final records = o + 2;

          final back = skipper.backward(buf, pos, backtrackCount);
          if (back == null) continue;
          var ok = true;
          for (var i = 0; i < backtrackCount; i++) {
            if (buf[back[i]].gid != backtrack[i]) {
              ok = false;
              break;
            }
          }
          if (!ok) continue;

          final inputPositions = skipper.forward(buf, pos, inputCount - 1);
          if (inputPositions == null) continue;
          for (var i = 0; i < inputCount - 1; i++) {
            if (buf[inputPositions[i]].gid != input[i]) {
              ok = false;
              break;
            }
          }
          if (!ok) continue;

          final tailStart = inputPositions.isEmpty ? pos : inputPositions.last;
          final ahead = skipper.forward(buf, tailStart, lookaheadCount);
          if (ahead == null) continue;
          for (var i = 0; i < lookaheadCount; i++) {
            if (buf[ahead[i]].gid != lookahead[i]) {
              ok = false;
              break;
            }
          }
          if (!ok) continue;

          return _applyRecords(
            buf,
            [pos, ...inputPositions],
            records,
            recordCount,
          );
        }
        return null;

      case 2:
        final coverage = Coverage.parse(d, sub + d.u16(sub + 2));
        if (coverage.indexOf(buf[pos].gid) == null) return null;
        final backtrackClass = ClassDef.parse(d, sub + d.u16(sub + 4));
        final inputClass = ClassDef.parse(d, sub + d.u16(sub + 6));
        final lookaheadClass = ClassDef.parse(d, sub + d.u16(sub + 8));
        final setCount = d.u16(sub + 10);
        final startClass = inputClass.of(buf[pos].gid);
        if (startClass >= setCount) return null;
        final setOffset = d.u16(sub + 12 + 2 * startClass);
        if (setOffset == 0) return null;
        final set = sub + setOffset;
        final ruleCount = d.u16(set);
        for (var r = 0; r < ruleCount; r++) {
          var o = set + d.u16(set + 2 + 2 * r);
          final backtrackCount = d.u16(o);
          final backtrack = <int>[
            for (var i = 0; i < backtrackCount; i++) d.u16(o + 2 + 2 * i),
          ];
          o += 2 + 2 * backtrackCount;
          final inputCount = d.u16(o);
          if (inputCount == 0) continue;
          final input = <int>[
            for (var i = 0; i < inputCount - 1; i++) d.u16(o + 2 + 2 * i),
          ];
          o += 2 + 2 * (inputCount - 1);
          final lookaheadCount = d.u16(o);
          final lookahead = <int>[
            for (var i = 0; i < lookaheadCount; i++) d.u16(o + 2 + 2 * i),
          ];
          o += 2 + 2 * lookaheadCount;
          final recordCount = d.u16(o);
          final records = o + 2;

          final back = skipper.backward(buf, pos, backtrackCount);
          if (back == null) continue;
          var ok = true;
          for (var i = 0; i < backtrackCount; i++) {
            if (backtrackClass.of(buf[back[i]].gid) != backtrack[i]) {
              ok = false;
              break;
            }
          }
          if (!ok) continue;

          final inputPositions = skipper.forward(buf, pos, inputCount - 1);
          if (inputPositions == null) continue;
          for (var i = 0; i < inputCount - 1; i++) {
            if (inputClass.of(buf[inputPositions[i]].gid) != input[i]) {
              ok = false;
              break;
            }
          }
          if (!ok) continue;

          final tailStart = inputPositions.isEmpty ? pos : inputPositions.last;
          final ahead = skipper.forward(buf, tailStart, lookaheadCount);
          if (ahead == null) continue;
          for (var i = 0; i < lookaheadCount; i++) {
            if (lookaheadClass.of(buf[ahead[i]].gid) != lookahead[i]) {
              ok = false;
              break;
            }
          }
          if (!ok) continue;

          return _applyRecords(
            buf,
            [pos, ...inputPositions],
            records,
            recordCount,
          );
        }
        return null;

      case 3:
        var o = sub + 2;
        final backtrackCount = d.u16(o);
        final backtrackCov = <int>[
          for (var i = 0; i < backtrackCount; i++) sub + d.u16(o + 2 + 2 * i),
        ];
        o += 2 + 2 * backtrackCount;
        final inputCount = d.u16(o);
        if (inputCount == 0) return null;
        final inputCov = <int>[
          for (var i = 0; i < inputCount; i++) sub + d.u16(o + 2 + 2 * i),
        ];
        o += 2 + 2 * inputCount;
        final lookaheadCount = d.u16(o);
        final lookaheadCov = <int>[
          for (var i = 0; i < lookaheadCount; i++) sub + d.u16(o + 2 + 2 * i),
        ];
        o += 2 + 2 * lookaheadCount;
        final recordCount = d.u16(o);
        final records = o + 2;

        if (Coverage.parse(d, inputCov[0]).indexOf(buf[pos].gid) == null) {
          return null;
        }
        final back = skipper.backward(buf, pos, backtrackCount);
        if (back == null) return null;
        for (var i = 0; i < backtrackCount; i++) {
          if (Coverage.parse(d, backtrackCov[i]).indexOf(buf[back[i]].gid) ==
              null) {
            return null;
          }
        }
        final inputPositions = skipper.forward(buf, pos, inputCount - 1);
        if (inputPositions == null) return null;
        for (var i = 1; i < inputCount; i++) {
          if (Coverage.parse(d, inputCov[i])
                  .indexOf(buf[inputPositions[i - 1]].gid) ==
              null) {
            return null;
          }
        }
        final tailStart = inputPositions.isEmpty ? pos : inputPositions.last;
        final ahead = skipper.forward(buf, tailStart, lookaheadCount);
        if (ahead == null) return null;
        for (var i = 0; i < lookaheadCount; i++) {
          if (Coverage.parse(d, lookaheadCov[i]).indexOf(buf[ahead[i]].gid) ==
              null) {
            return null;
          }
        }
        return _applyRecords(
          buf,
          [pos, ...inputPositions],
          records,
          recordCount,
        );

      default:
        return null;
    }
  }
}
