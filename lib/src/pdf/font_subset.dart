/// Cuts a TrueType font down to the glyphs a document actually draws.
///
/// A Bengali font is mostly outlines — `glyf` is 85% of the bundled Kalpurush
/// and 62% of Noto Sans Bengali — and a document uses a few dozen of them. The
/// layout tables are pure waste in a PDF as well: shaping has already been
/// applied, so `GSUB`, `GPOS` and `GDEF` are never consulted by a reader.
///
/// Glyph ids are **preserved**. Blanking unused outlines rather than
/// renumbering keeps `/CIDToGIDMap`, the `/W` array and `/ToUnicode` exactly as
/// they were, and costs only the `loca` entries for glyphs that are now empty
/// — four bytes each, against hundreds saved per dropped outline.
library;

import 'dart:typed_data';

/// Tables a reader never consults for an already-shaped, Identity-H CID font.
const _drop = <String>{
  'GSUB', 'GPOS', 'GDEF', // shaping, already applied
  'hdmx', 'VDMX', 'LTSH', 'gasp', // screen-rendering hints
  'DSIG', // signature, invalid the moment we edit anything
  'kern', // superseded by GPOS, and we position glyphs ourselves
};

/// Returns [source] with only [usedGids] (and anything they reference) kept.
///
/// Returns `null` when the font cannot be subset safely — a CFF outline font,
/// a malformed table directory, a missing `glyf` — in which case the caller
/// should embed the original.
Uint8List? subsetTrueType(ByteData source, Set<int> usedGids) {
  final tables = _directory(source);
  if (tables == null) return null;

  final head = tables['head'];
  final maxp = tables['maxp'];
  final loca = tables['loca'];
  final glyf = tables['glyf'];
  if (head == null || maxp == null || loca == null || glyf == null) return null;
  if (head.length < 54 || maxp.length < 6) return null;

  final numGlyphs = source.getUint16(maxp.offset + 4);
  if (numGlyphs == 0) return null;

  final longLoca = source.getInt16(head.offset + 50) != 0;
  final offsets = _readLoca(source, loca, numGlyphs, longLoca: longLoca);
  if (offsets == null) return null;

  // A composite glyph draws other glyphs, which must survive with it.
  final keep = <int>{0}; // .notdef is always glyph 0
  final pending = <int>[...usedGids.where((g) => g >= 0 && g < numGlyphs), 0];
  while (pending.isNotEmpty) {
    final gid = pending.removeLast();
    if (!keep.add(gid)) continue;
    for (final component in _components(source, glyf, offsets, gid)) {
      if (component >= 0 &&
          component < numGlyphs &&
          !keep.contains(component)) {
        pending.add(component);
      }
    }
  }

  // Rebuild glyf and loca, keeping every glyph id.
  final newGlyf = BytesBuilder(copy: false);
  final newOffsets = Uint32List(numGlyphs + 1);
  for (var gid = 0; gid < numGlyphs; gid++) {
    newOffsets[gid] = newGlyf.length;
    if (!keep.contains(gid)) continue;
    final start = offsets[gid];
    final end = offsets[gid + 1];
    if (end <= start) continue; // already an empty glyph
    if (glyf.offset + end > source.lengthInBytes) return null;
    newGlyf.add(
      source.buffer.asUint8List(
        source.offsetInBytes + glyf.offset + start,
        end - start,
      ),
    );
    // Glyph data is 4-byte aligned; short loca cannot express odd offsets.
    while (newGlyf.length % 4 != 0) {
      newGlyf.addByte(0);
    }
  }
  newOffsets[numGlyphs] = newGlyf.length;

  final glyfBytes = newGlyf.takeBytes();
  // Short loca stores offsets halved, so it cannot address past 128 KB.
  final useLong = longLoca || glyfBytes.length > 0x1FFFF;
  final locaBytes = _writeLoca(newOffsets, long: useLong);

  final out = <String, Uint8List>{};
  for (final entry in tables.entries) {
    if (_drop.contains(entry.key)) continue;
    out[entry.key] = _slice(source, entry.value);
  }
  out['glyf'] = glyfBytes;
  out['loca'] = locaBytes;

  // `post` version 2 carries a glyph-name table -- 8 KB in Kalpurush -- that a
  // PDF reader never reads. Version 3 declares "no names" in 32 bytes.
  final post = out['post'];
  if (post != null && post.length > 32) {
    final v3 = Uint8List(32)..setRange(0, 32, post.sublist(0, 32));
    final view = ByteData.sublistView(v3);
    view.setUint32(0, 0x00030000);
    out['post'] = v3;
  }

  // head records which loca format we just wrote.
  final headBytes = Uint8List.fromList(out['head']!);
  ByteData.sublistView(headBytes).setInt16(50, useLong ? 1 : 0);
  out['head'] = headBytes;

  return _assemble(out);
}

/// One entry in the sfnt table directory.
class _Table {
  const _Table(this.offset, this.length);
  final int offset;
  final int length;
}

Map<String, _Table>? _directory(ByteData d) {
  if (d.lengthInBytes < 12) return null;
  final version = d.getUint32(0);
  // 0x00010000 is TrueType outlines; 'true' is the old Apple tag. 'OTTO' is
  // CFF, whose outlines live in a table this cannot rebuild.
  if (version != 0x00010000 && version != 0x74727565) return null;

  final count = d.getUint16(4);
  if (12 + count * 16 > d.lengthInBytes) return null;
  final out = <String, _Table>{};
  for (var i = 0; i < count; i++) {
    final row = 12 + i * 16;
    final tag = String.fromCharCodes(<int>[
      for (var k = 0; k < 4; k++) d.getUint8(row + k),
    ]);
    final offset = d.getUint32(row + 8);
    final length = d.getUint32(row + 12);
    if (offset + length > d.lengthInBytes) return null;
    out[tag] = _Table(offset, length);
  }
  return out;
}

Uint8List _slice(ByteData d, _Table t) => Uint8List.fromList(
    d.buffer.asUint8List(d.offsetInBytes + t.offset, t.length));

List<int>? _readLoca(
  ByteData d,
  _Table loca,
  int numGlyphs, {
  required bool longLoca,
}) {
  final need = (numGlyphs + 1) * (longLoca ? 4 : 2);
  if (loca.length < need) return null;
  final out = List<int>.filled(numGlyphs + 1, 0);
  for (var i = 0; i <= numGlyphs; i++) {
    out[i] = longLoca
        ? d.getUint32(loca.offset + i * 4)
        : d.getUint16(loca.offset + i * 2) * 2;
  }
  return out;
}

Uint8List _writeLoca(Uint32List offsets, {required bool long}) {
  final out = Uint8List(offsets.length * (long ? 4 : 2));
  final view = ByteData.sublistView(out);
  for (var i = 0; i < offsets.length; i++) {
    if (long) {
      view.setUint32(i * 4, offsets[i]);
    } else {
      view.setUint16(i * 2, offsets[i] ~/ 2);
    }
  }
  return out;
}

/// Glyph ids a composite glyph draws, or empty for a simple one.
Iterable<int> _components(
  ByteData d,
  _Table glyf,
  List<int> offsets,
  int gid,
) sync* {
  if (gid + 1 >= offsets.length) return;
  final start = glyf.offset + offsets[gid];
  if (offsets[gid + 1] <= offsets[gid]) return;
  if (start + 10 > d.lengthInBytes) return;
  if (d.getInt16(start) >= 0) return; // simple glyph

  var at = start + 10;
  while (at + 4 <= d.lengthInBytes) {
    final flags = d.getUint16(at);
    yield d.getUint16(at + 2);
    at += 4;
    at += (flags & 0x0001) != 0 ? 4 : 2; // ARG_1_AND_2_ARE_WORDS
    if ((flags & 0x0008) != 0) {
      at += 2; // WE_HAVE_A_SCALE
    } else if ((flags & 0x0040) != 0) {
      at += 4; // WE_HAVE_AN_X_AND_Y_SCALE
    } else if ((flags & 0x0080) != 0) {
      at += 8; // WE_HAVE_A_TWO_BY_TWO
    }
    if ((flags & 0x0020) == 0) return; // MORE_COMPONENTS
  }
}

/// Writes [tables] as a valid sfnt, with the checksums a validator expects.
Uint8List _assemble(Map<String, Uint8List> tables) {
  final tags = tables.keys.toList()..sort();
  final count = tags.length;
  var offset = 12 + count * 16;
  final starts = <String, int>{};
  for (final tag in tags) {
    starts[tag] = offset;
    offset += (tables[tag]!.length + 3) & ~3;
  }

  final out = Uint8List(offset);
  final view = ByteData.sublistView(out);
  view.setUint32(0, 0x00010000);
  view.setUint16(4, count);
  // searchRange, entrySelector and rangeShift, per the sfnt header.
  var power = 1;
  var selector = 0;
  while (power * 2 <= count) {
    power *= 2;
    selector++;
  }
  view.setUint16(6, power * 16);
  view.setUint16(8, selector);
  view.setUint16(10, count * 16 - power * 16);

  for (var i = 0; i < count; i++) {
    final tag = tags[i];
    final data = tables[tag]!;
    final row = 12 + i * 16;
    for (var k = 0; k < 4; k++) {
      view.setUint8(row + k, tag.codeUnitAt(k));
    }
    out.setRange(starts[tag]!, starts[tag]! + data.length, data);
    view.setUint32(row + 4, _checksum(view, starts[tag]!, data.length));
    view.setUint32(row + 8, starts[tag]!);
    view.setUint32(row + 12, data.length);
  }

  // head.checkSumAdjustment is defined over the finished file, so it is zeroed
  // while the total is taken and written last.
  final headStart = starts['head'];
  if (headStart != null && tables['head']!.length >= 12) {
    view.setUint32(headStart + 8, 0);
    final total = _checksum(view, 0, out.length);
    view.setUint32(headStart + 8, (0xB1B0AFBA - total) & 0xFFFFFFFF);
  }
  return out;
}

int _checksum(ByteData d, int start, int length) {
  var sum = 0;
  final words = (length + 3) ~/ 4;
  for (var i = 0; i < words; i++) {
    final at = start + i * 4;
    var value = 0;
    for (var k = 0; k < 4; k++) {
      value =
          (value << 8) | (at + k < d.lengthInBytes ? d.getUint8(at + k) : 0);
    }
    sum = (sum + value) & 0xFFFFFFFF;
  }
  return sum;
}
