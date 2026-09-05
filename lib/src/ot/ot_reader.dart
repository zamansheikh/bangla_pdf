/// Low-level OpenType binary primitives: safe readers, Coverage and ClassDef.
///
/// Every reader is bounds-checked and returns a benign default rather than
/// throwing, because we parse fonts supplied by users at runtime and a
/// malformed table must never abort PDF generation.
library;

import 'dart:typed_data';

/// A bounds-checked cursor over a font's bytes.
class OtData {
  OtData(this.bytes) : _len = bytes.lengthInBytes;

  final ByteData bytes;
  final int _len;

  bool has(int offset, int length) =>
      offset >= 0 && length >= 0 && offset + length <= _len;

  int u8(int o) => has(o, 1) ? bytes.getUint8(o) : 0;

  int u16(int o) => has(o, 2) ? bytes.getUint16(o) : 0;

  int i16(int o) => has(o, 2) ? bytes.getInt16(o) : 0;

  int u32(int o) => has(o, 4) ? bytes.getUint32(o) : 0;

  String tag(int o) {
    if (!has(o, 4)) return '    ';
    return String.fromCharCodes([u8(o), u8(o + 1), u8(o + 2), u8(o + 3)]);
  }
}

/// OpenType Coverage table (formats 1 and 2).
///
/// Maps a glyph id to its coverage index, or `null` when not covered.
class Coverage {
  Coverage._(this._single, this._ranges);

  /// Parses the Coverage table at [offset]. Never throws.
  factory Coverage.parse(OtData d, int offset) {
    switch (d.u16(offset)) {
      case 1:
        final count = d.u16(offset + 2);
        final map = <int, int>{};
        for (var i = 0; i < count; i++) {
          map[d.u16(offset + 4 + 2 * i)] = i;
        }
        return Coverage._(map, const []);
      case 2:
        final count = d.u16(offset + 2);
        final ranges = <CovRange>[];
        for (var i = 0; i < count; i++) {
          final o = offset + 4 + 6 * i;
          ranges.add(CovRange(d.u16(o), d.u16(o + 2), d.u16(o + 4)));
        }
        return Coverage._(const {}, ranges);
      default:
        return Coverage._(const {}, const []);
    }
  }

  final Map<int, int> _single;
  final List<CovRange> _ranges;

  /// Coverage index of [glyph], or `null` if the glyph is not covered.
  int? indexOf(int glyph) {
    final direct = _single[glyph];
    if (direct != null) return direct;
    // Ranges are sorted by start glyph, so binary search is safe.
    var lo = 0;
    var hi = _ranges.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final r = _ranges[mid];
      if (glyph < r.start) {
        hi = mid - 1;
      } else if (glyph > r.end) {
        lo = mid + 1;
      } else {
        return r.value + (glyph - r.start);
      }
    }
    return null;
  }

  bool covers(int glyph) => indexOf(glyph) != null;

  /// Covered glyph ids in coverage-index order.
  ///
  /// Needed to walk a subtable's parallel arrays, where entry *i* belongs to
  /// the glyph whose coverage index is *i*.
  List<int> get glyphs {
    final out = <int>[];
    for (final entry in _single.entries) {
      while (out.length <= entry.value) {
        out.add(0);
      }
      out[entry.value] = entry.key;
    }
    for (final range in _ranges) {
      for (var g = range.start; g <= range.end; g++) {
        final index = range.value + (g - range.start);
        while (out.length <= index) {
          out.add(0);
        }
        out[index] = g;
      }
    }
    return out;
  }
}

/// A `[start, end] -> value` range, shared by Coverage and ClassDef format 2.
class CovRange {
  const CovRange(this.start, this.end, this.value);
  final int start;
  final int end;
  final int value;
}

/// OpenType ClassDef table (formats 1 and 2). Unlisted glyphs are class 0.
class ClassDef {
  ClassDef._(this._startGlyph, this._values, this._ranges);

  /// Parses the ClassDef at [offset]. An [offset] of 0 yields an all-zero table.
  factory ClassDef.parse(OtData d, int offset) {
    if (offset == 0) return ClassDef._(0, const [], const []);
    switch (d.u16(offset)) {
      case 1:
        final start = d.u16(offset + 2);
        final count = d.u16(offset + 4);
        final values = <int>[
          for (var i = 0; i < count; i++) d.u16(offset + 6 + 2 * i),
        ];
        return ClassDef._(start, values, const []);
      case 2:
        final count = d.u16(offset + 2);
        final ranges = <CovRange>[];
        for (var i = 0; i < count; i++) {
          final o = offset + 4 + 6 * i;
          ranges.add(CovRange(d.u16(o), d.u16(o + 2), d.u16(o + 4)));
        }
        return ClassDef._(0, const [], ranges);
      default:
        return ClassDef._(0, const [], const []);
    }
  }

  final int _startGlyph;
  final List<int> _values;
  final List<CovRange> _ranges;

  /// Class value of [glyph]; 0 when the glyph is not listed.
  int of(int glyph) {
    if (_values.isNotEmpty) {
      final i = glyph - _startGlyph;
      return (i >= 0 && i < _values.length) ? _values[i] : 0;
    }
    var lo = 0;
    var hi = _ranges.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final r = _ranges[mid];
      if (glyph < r.start) {
        hi = mid - 1;
      } else if (glyph > r.end) {
        lo = mid + 1;
      } else {
        return r.value;
      }
    }
    return 0;
  }
}
