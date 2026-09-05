/// GPOS glyph positioning.
///
/// Implements lookup types 1 (single), 2 (pair), 4 (mark-to-base), 5
/// (mark-to-ligature), 6 (mark-to-mark), 8 (chained context) and 9
/// (extension). Types 3 and 7 are skipped: cursive attachment and plain
/// context positioning are not used by the Bengali fonts in the corpus, and an
/// unimplemented type is ignored rather than mis-applied.
library;

import 'package:bangla_pdf/src/ot/glyph_buffer.dart';
import 'package:bangla_pdf/src/ot/ot_font.dart';
import 'package:bangla_pdf/src/ot/ot_reader.dart';

/// Applies GPOS lookups to a shaped glyph buffer.
class GposEngine {
  GposEngine(this.font, this.table) : d = font.d;

  final OtFont font;
  final LayoutTable table;
  final OtData d;

  static const int _maxRecursionDepth = 8;
  int _depth = 0;

  /// Feature tags applied for Bengali, in order.
  static const List<String> _features = <String>[
    // HarfBuzz applies cursive joining before the Indic positioning features,
    // for every script. No Bengali font carries it, but a font that does joins
    // its glyphs into a continuous stroke and looks broken without it.
    'curs',
    'dist',
    'abvm',
    'blwm',
    'mark',
    'mkmk',
    'kern',
  ];

  /// Applies the Bengali positioning features from [featureLookups].
  void apply(List<GlyphInfo> buf, Map<String, List<int>> featureLookups) {
    for (final tag in _features) {
      final lookups = featureLookups[tag];
      if (lookups == null) continue;
      for (final index in lookups) {
        _applyLookup(buf, index);
      }
    }
    _resolveAttachments(buf);
  }

  void _applyLookup(List<GlyphInfo> buf, int lookupIndex) {
    final lookup = table.lookupOffset(lookupIndex);
    if (lookup == null) return;
    final type = d.u16(lookup);
    final flags = d.u16(lookup + 2);
    var i = 0;
    var guard = 0;
    final maxSteps = buf.length * 8 + 256;
    while (i < buf.length) {
      if (++guard > maxSteps) break;
      final advance = _applyAt(buf, i, lookup, type, flags);
      i += (advance == null || advance <= 0) ? 1 : advance;
    }
  }

  bool _applyLookupAt(List<GlyphInfo> buf, int pos, int lookupIndex) {
    if (_depth >= _maxRecursionDepth) return false;
    final lookup = table.lookupOffset(lookupIndex);
    if (lookup == null || pos < 0 || pos >= buf.length) return false;
    _depth++;
    try {
      return _applyAt(buf, pos, lookup, d.u16(lookup), d.u16(lookup + 2)) !=
          null;
    } finally {
      _depth--;
    }
  }

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
      var sub = lookup + d.u16(lookup + 6 + 2 * s);
      var effectiveType = type;
      if (type == 9) {
        if (d.u16(sub) != 1) continue;
        effectiveType = d.u16(sub + 2);
        sub = sub + d.u32(sub + 4);
      }
      final r = switch (effectiveType) {
        1 => _single(buf, pos, sub),
        2 => _pair(buf, pos, sub, flags, markFilteringSet),
        3 => _cursive(buf, pos, sub, flags, markFilteringSet),
        4 => _markToBase(buf, pos, sub),
        5 => _markToLigature(buf, pos, sub),
        6 => _markToMark(buf, pos, sub, flags, markFilteringSet),
        8 => _chainContext(buf, pos, sub, flags, markFilteringSet),
        _ => null,
      };
      if (r != null) return r;
    }
    return null;
  }

  // --- ValueRecord ----------------------------------------------------------

  static int _valueRecordSize(int format) {
    var size = 0;
    for (var bit = 0; bit < 8; bit++) {
      if (format & (1 << bit) != 0) size += 2;
    }
    return size;
  }

  /// Applies a ValueRecord at [offset] to [g]. Device tables are ignored.
  void _applyValue(GlyphInfo g, int offset, int format) {
    var o = offset;
    if (format & 0x0001 != 0) {
      g.xOffset += d.i16(o);
      o += 2;
    }
    if (format & 0x0002 != 0) {
      g.yOffset += d.i16(o);
      o += 2;
    }
    if (format & 0x0004 != 0) {
      g.xAdvance += d.i16(o);
      o += 2;
    }
    if (format & 0x0008 != 0) {
      g.yAdvance += d.i16(o);
    }
  }

  // --- Type 1: single adjustment --------------------------------------------

  int? _single(List<GlyphInfo> buf, int pos, int sub) {
    final format = d.u16(sub);
    final coverage = Coverage.parse(d, sub + d.u16(sub + 2));
    final index = coverage.indexOf(buf[pos].gid);
    if (index == null) return null;
    final valueFormat = d.u16(sub + 4);
    if (format == 1) {
      _applyValue(buf[pos], sub + 6, valueFormat);
      return 1;
    }
    if (format == 2) {
      if (index >= d.u16(sub + 6)) return null;
      final size = _valueRecordSize(valueFormat);
      _applyValue(buf[pos], sub + 8 + size * index, valueFormat);
      return 1;
    }
    return null;
  }

  // --- Type 2: pair adjustment ----------------------------------------------

  int? _pair(
    List<GlyphInfo> buf,
    int pos,
    int sub,
    int flags,
    int markFilteringSet,
  ) {
    final skipper =
        SkipFilter(font, flags, markFilteringSet, buf[pos].syllable);
    final next = skipper.next(buf, pos);
    if (next == null) return null;
    final format = d.u16(sub);
    final coverage = Coverage.parse(d, sub + d.u16(sub + 2));
    final index = coverage.indexOf(buf[pos].gid);
    if (index == null) return null;
    final format1 = d.u16(sub + 4);
    final format2 = d.u16(sub + 6);
    final size1 = _valueRecordSize(format1);
    final size2 = _valueRecordSize(format2);

    if (format == 1) {
      if (index >= d.u16(sub + 8)) return null;
      final set = sub + d.u16(sub + 10 + 2 * index);
      final count = d.u16(set);
      final recordSize = 2 + size1 + size2;
      for (var i = 0; i < count; i++) {
        final rec = set + 2 + recordSize * i;
        if (d.u16(rec) != buf[next].gid) continue;
        if (format1 != 0) _applyValue(buf[pos], rec + 2, format1);
        if (format2 != 0) _applyValue(buf[next], rec + 2 + size1, format2);
        return format2 != 0 ? 2 : 1;
      }
      return null;
    }

    if (format == 2) {
      final class1 = ClassDef.parse(d, sub + d.u16(sub + 8));
      final class2 = ClassDef.parse(d, sub + d.u16(sub + 10));
      final class1Count = d.u16(sub + 12);
      final class2Count = d.u16(sub + 14);
      final c1 = class1.of(buf[pos].gid);
      final c2 = class2.of(buf[next].gid);
      if (c1 >= class1Count || c2 >= class2Count) return null;
      final recordSize = size1 + size2;
      final rec = sub + 16 + (c1 * class2Count + c2) * recordSize;
      if (format1 != 0) _applyValue(buf[pos], rec, format1);
      if (format2 != 0) _applyValue(buf[next], rec + size1, format2);
      return format2 != 0 ? 2 : 1;
    }
    return null;
  }

  // --- Anchors --------------------------------------------------------------

  /// Reads an anchor table, returning `(x, y)` in font units.
  (int, int)? _anchor(int offset) {
    if (offset == 0) return null;
    final format = d.u16(offset);
    if (format < 1 || format > 3) return null;
    return (d.i16(offset + 2), d.i16(offset + 4));
  }

  // --- Types 4, 5, 6: mark attachment ---------------------------------------

  /// Index of the glyph a mark at [pos] attaches to.
  ///
  /// Mark-to-base and mark-to-ligature always step over every mark, whatever
  /// the lookup's own flags say. Mark-to-mark instead honours the lookup's
  /// flags *and* its mark filtering set, so a mark can attach to an earlier
  /// mark with other marks in between — which is how ৃ reaches the base of
  /// স্কৃ past two intervening pieces.
  int? _attachmentTarget(
    List<GlyphInfo> buf,
    int pos, {
    required bool baseIsMark,
    int flags = 0,
    int markFilteringSet = -1,
  }) {
    if (!baseIsMark) {
      for (var i = pos - 1; i >= 0; i--) {
        if (!font.isMark(buf[i].gid)) return i;
      }
      return null;
    }
    final skipper = SkipFilter(font, flags, markFilteringSet);
    final previous = skipper.previous(buf, pos);
    if (previous == null) return null;
    return font.isMark(buf[previous].gid) ? previous : null;
  }

  /// Shared body for mark-to-base and mark-to-mark.
  int? _markAttach(
    List<GlyphInfo> buf,
    int pos,
    int sub, {
    required bool baseIsMark,
    int flags = 0,
    int markFilteringSet = -1,
  }) {
    if (d.u16(sub) != 1) return null;
    final markCoverage = Coverage.parse(d, sub + d.u16(sub + 2));
    final markIndex = markCoverage.indexOf(buf[pos].gid);
    if (markIndex == null) return null;

    final basePos = _attachmentTarget(
      buf,
      pos,
      baseIsMark: baseIsMark,
      flags: flags,
      markFilteringSet: markFilteringSet,
    );
    if (basePos == null) return null;

    final baseCoverage = Coverage.parse(d, sub + d.u16(sub + 4));
    final baseIndex = baseCoverage.indexOf(buf[basePos].gid);
    if (baseIndex == null) return null;

    final classCount = d.u16(sub + 6);
    final markArray = sub + d.u16(sub + 8);
    final baseArray = sub + d.u16(sub + 10);

    if (markIndex >= d.u16(markArray)) return null;
    final markRecord = markArray + 2 + 4 * markIndex;
    final markClass = d.u16(markRecord);
    if (markClass >= classCount) return null;
    final markAnchor = _anchor(markArray + d.u16(markRecord + 2));
    if (markAnchor == null) return null;

    if (baseIndex >= d.u16(baseArray)) return null;
    final baseAnchorOffset =
        d.u16(baseArray + 2 + (baseIndex * classCount + markClass) * 2);
    final baseAnchor = _anchor(baseArray + baseAnchorOffset);
    if (baseAnchor == null) return null;

    final mark = buf[pos];
    mark.xOffset = baseAnchor.$1 - markAnchor.$1;
    mark.yOffset = baseAnchor.$2 - markAnchor.$2;
    mark.attachChain = basePos - pos;
    mark.isAttached = true;
    // The advance is left alone: a mark's own hmtx advance is normally zero,
    // and a `dist` lookup may deliberately have given it a non-zero one.
    return 1;
  }

  // --- Type 3: cursive attachment -------------------------------------------

  /// Joins this glyph's exit anchor to the next glyph's entry anchor.
  ///
  /// How a joining script draws a continuous stroke through a word. No Bengali
  /// font uses it, but a font that does would otherwise fall apart, and the
  /// rule is the same for every script.
  int? _cursive(
    List<GlyphInfo> buf,
    int pos,
    int sub,
    int flags,
    int markFilteringSet,
  ) {
    if (d.u16(sub) != 1) return null;
    final coverage = Coverage.parse(d, sub + d.u16(sub + 2));
    final thisIndex = coverage.indexOf(buf[pos].gid);
    if (thisIndex == null) return null;
    final count = d.u16(sub + 4);
    if (thisIndex >= count) return null;

    final skipper = SkipFilter(font, flags, markFilteringSet);
    final next = skipper.next(buf, pos);
    if (next == null) return null;
    final nextIndex = coverage.indexOf(buf[next].gid);
    if (nextIndex == null || nextIndex >= count) return null;

    final exitOffset = d.u16(sub + 6 + thisIndex * 4 + 2);
    final entryOffset = d.u16(sub + 6 + nextIndex * 4);
    if (exitOffset == 0 || entryOffset == 0) return null;

    final exit = _anchor(sub + exitOffset);
    final entry = _anchor(sub + entryOffset);
    if (exit == null || entry == null) return null;

    // The exit point of this glyph and the entry point of the next become one
    // place, so the stroke runs on unbroken. This shapes left-to-right scripts
    // only -- Bengali is one -- so the slack comes off this glyph's advance;
    // a right-to-left script would take it off the next glyph instead.
    buf[pos].xAdvance = exit.$1 + buf[pos].xOffset;

    // Tying the baselines together is what makes the pair ride at one height.
    buf[next].yOffset = buf[pos].yOffset - (entry.$2 - exit.$2);
    buf[next].attachChain = pos - next;
    buf[next].isAttached = true;
    return 1;
  }

  int? _markToBase(List<GlyphInfo> buf, int pos, int sub) =>
      _markAttach(buf, pos, sub, baseIsMark: false);

  int? _markToMark(
    List<GlyphInfo> buf,
    int pos,
    int sub,
    int flags,
    int markFilteringSet,
  ) =>
      _markAttach(
        buf,
        pos,
        sub,
        baseIsMark: true,
        flags: flags,
        markFilteringSet: markFilteringSet,
      );

  /// Mark-to-ligature: like mark-to-base but the base carries one anchor set
  /// per ligature component. We attach to the last component, which is correct
  /// for Bengali where marks follow the whole conjunct.
  int? _markToLigature(List<GlyphInfo> buf, int pos, int sub) {
    if (d.u16(sub) != 1) return null;
    final markCoverage = Coverage.parse(d, sub + d.u16(sub + 2));
    final markIndex = markCoverage.indexOf(buf[pos].gid);
    if (markIndex == null) return null;

    final basePos = _attachmentTarget(buf, pos, baseIsMark: false);
    if (basePos == null) return null;

    final ligCoverage = Coverage.parse(d, sub + d.u16(sub + 4));
    final ligIndex = ligCoverage.indexOf(buf[basePos].gid);
    if (ligIndex == null) return null;

    final classCount = d.u16(sub + 6);
    final markArray = sub + d.u16(sub + 8);
    final ligArray = sub + d.u16(sub + 10);

    if (markIndex >= d.u16(markArray)) return null;
    final markRecord = markArray + 2 + 4 * markIndex;
    final markClass = d.u16(markRecord);
    if (markClass >= classCount) return null;
    final markAnchor = _anchor(markArray + d.u16(markRecord + 2));
    if (markAnchor == null) return null;

    if (ligIndex >= d.u16(ligArray)) return null;
    final ligAttach = ligArray + d.u16(ligArray + 2 + 2 * ligIndex);
    final componentCount = d.u16(ligAttach);
    if (componentCount == 0) return null;
    final component = componentCount - 1;
    final ligAnchorOffset = d.u16(
      ligAttach + 2 + (component * classCount + markClass) * 2,
    );
    final ligAnchor = _anchor(ligAttach + ligAnchorOffset);
    if (ligAnchor == null) return null;

    final mark = buf[pos];
    mark.xOffset = ligAnchor.$1 - markAnchor.$1;
    mark.yOffset = ligAnchor.$2 - markAnchor.$2;
    mark.attachChain = basePos - pos;
    mark.isAttached = true;
    return 1;
  }

  // --- Type 8: chained context positioning ----------------------------------

  int _applyRecords(
    List<GlyphInfo> buf,
    List<int> inputPositions,
    int recordsOffset,
    int recordCount,
  ) {
    for (var r = 0; r < recordCount; r++) {
      final o = recordsOffset + 4 * r;
      final sequenceIndex = d.u16(o);
      final lookupIndex = d.u16(o + 2);
      if (sequenceIndex >= inputPositions.length) continue;
      // GPOS never changes buffer length, so positions stay valid.
      _applyLookupAt(buf, inputPositions[sequenceIndex], lookupIndex);
    }
    final advance = inputPositions.isEmpty
        ? 1
        : inputPositions.last - inputPositions.first + 1;
    return advance <= 0 ? 1 : advance;
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

    if (format == 3) {
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
      final input = skipper.forward(buf, pos, inputCount - 1);
      if (input == null) return null;
      for (var i = 1; i < inputCount; i++) {
        if (Coverage.parse(d, inputCov[i]).indexOf(buf[input[i - 1]].gid) ==
            null) {
          return null;
        }
      }
      final tail = input.isEmpty ? pos : input.last;
      final ahead = skipper.forward(buf, tail, lookaheadCount);
      if (ahead == null) return null;
      for (var i = 0; i < lookaheadCount; i++) {
        if (Coverage.parse(d, lookaheadCov[i]).indexOf(buf[ahead[i]].gid) ==
            null) {
          return null;
        }
      }
      return _applyRecords(buf, [pos, ...input], records, recordCount);
    }

    if (format == 2) {
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
        final inputClasses = <int>[
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
        final input = skipper.forward(buf, pos, inputCount - 1);
        if (input == null) continue;
        for (var i = 0; i < inputCount - 1; i++) {
          if (inputClass.of(buf[input[i]].gid) != inputClasses[i]) {
            ok = false;
            break;
          }
        }
        if (!ok) continue;
        final tail = input.isEmpty ? pos : input.last;
        final ahead = skipper.forward(buf, tail, lookaheadCount);
        if (ahead == null) continue;
        for (var i = 0; i < lookaheadCount; i++) {
          if (lookaheadClass.of(buf[ahead[i]].gid) != lookahead[i]) {
            ok = false;
            break;
          }
        }
        if (!ok) continue;
        return _applyRecords(buf, [pos, ...input], records, recordCount);
      }
      return null;
    }

    return null;
  }

  /// Folds attachment chains into absolute offsets.
  ///
  /// A mark's anchor offset is relative to the glyph it attaches to, which may
  /// itself be an attached mark. Marks always attach backwards, so a single
  /// ascending pass resolves every chain: by the time glyph `i` is reached its
  /// parent already holds an absolute offset.
  void _resolveAttachments(List<GlyphInfo> buf) {
    for (var i = 0; i < buf.length; i++) {
      final g = buf[i];
      if (!g.isAttached) continue;
      final parent = i + g.attachChain;
      if (parent < 0 || parent >= i) continue;
      g.xOffset += buf[parent].xOffset;
      g.yOffset += buf[parent].yOffset;
      // Back out the advances between the parent and this mark, since the pen
      // has already moved past them.
      for (var k = parent; k < i; k++) {
        g.xOffset -= buf[k].xAdvance;
        g.yOffset -= buf[k].yAdvance;
      }
    }
  }
}
