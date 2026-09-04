/// PDF stream filters.
///
/// Covers the filters that appear in real documents: `FlateDecode` (with PNG
/// and TIFF predictors), `LZWDecode`, `ASCIIHexDecode`, `ASCII85Decode` and
/// `RunLengthDecode`. Image filters (`DCTDecode`, `JPXDecode`, `CCITTFaxDecode`)
/// are left encoded — extraction never needs their pixels, only to know they
/// are there.
library;

import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bangla_pdf/src/extract/pdf_object.dart';

/// Filters whose output is image data, not something to decode here.
const Set<String> imageFilters = <String>{
  'DCTDecode',
  'DCT',
  'JPXDecode',
  'CCITTFaxDecode',
  'CCF',
  'JBIG2Decode',
};

/// Decodes [raw] according to the stream dictionary [dict].
///
/// Returns `null` when the data is an encoded image, and the bytes unchanged
/// when a filter is unrecognised — a partially-decoded stream is more useful
/// than none.
Uint8List? decodeStream(
    Uint8List raw, PdfDictObj dict, PdfObj? Function(PdfObj) resolve) {
  final filterObj = resolve(dict['Filter']);
  final parmsObj = resolve(dict['DecodeParms']);

  final filters = <String>[];
  if (filterObj is PdfNameObj) {
    filters.add(filterObj.value);
  } else if (filterObj is PdfArrayObj) {
    for (final f in filterObj.values) {
      final r = resolve(f);
      if (r is PdfNameObj) filters.add(r.value);
    }
  }

  final parms = <PdfDictObj?>[];
  if (parmsObj is PdfDictObj) {
    parms.add(parmsObj);
  } else if (parmsObj is PdfArrayObj) {
    for (final p in parmsObj.values) {
      final r = resolve(p);
      parms.add(r is PdfDictObj ? r : null);
    }
  }

  var data = raw;
  for (var i = 0; i < filters.length; i++) {
    final name = filters[i];
    if (imageFilters.contains(name)) return null;
    final parm = i < parms.length ? parms[i] : null;
    switch (name) {
      case 'FlateDecode':
      case 'Fl':
        data = _applyPredictor(_inflate(data), parm, resolve);
      case 'LZWDecode':
      case 'LZW':
        data = _applyPredictor(
            _lzwDecode(data, _earlyChange(parm, resolve)), parm, resolve);
      case 'ASCIIHexDecode':
      case 'AHx':
        data = _asciiHexDecode(data);
      case 'ASCII85Decode':
      case 'A85':
        data = _ascii85Decode(data);
      case 'RunLengthDecode':
      case 'RL':
        data = _runLengthDecode(data);
      default:
        // Crypt, or something we do not know: leave it as-is.
        break;
    }
  }
  return data;
}

int _earlyChange(PdfDictObj? parm, PdfObj? Function(PdfObj) resolve) {
  if (parm == null) return 1;
  final v = resolve(parm['EarlyChange']);
  return v is PdfNumObj ? v.asInt : 1;
}

Uint8List _inflate(Uint8List data) {
  if (data.isEmpty) return data;
  try {
    return const ZLibDecoder().decodeBytes(data);
  } catch (_) {
    // Some writers emit raw deflate, or a stream with trailing junk. Retry
    // without the zlib header before giving up.
    try {
      return Uint8List.fromList(Inflate(data).getBytes());
    } catch (_) {
      if (data.length > 2) {
        try {
          return Uint8List.fromList(
            Inflate(Uint8List.sublistView(data, 2)).getBytes(),
          );
        } catch (_) {
          // fall through
        }
      }
      return Uint8List(0);
    }
  }
}

/// Undoes PNG (predictor >= 10) or TIFF (predictor 2) prediction.
Uint8List _applyPredictor(
  Uint8List data,
  PdfDictObj? parm,
  PdfObj? Function(PdfObj) resolve,
) {
  if (parm == null || data.isEmpty) return data;
  int intOf(String key, int fallback) {
    final v = resolve(parm[key]);
    return v is PdfNumObj ? v.asInt : fallback;
  }

  final predictor = intOf('Predictor', 1);
  if (predictor <= 1) return data;

  final colors = intOf('Colors', 1);
  final bpc = intOf('BitsPerComponent', 8);
  final columns = intOf('Columns', 1);
  final bpp = ((colors * bpc) / 8).ceil().clamp(1, 64);
  final rowLength = ((columns * colors * bpc) / 8).ceil();
  if (rowLength <= 0) return data;

  if (predictor == 2) {
    if (bpc != 8) return data;
    final out = Uint8List.fromList(data);
    for (var r = 0; r + rowLength <= out.length; r += rowLength) {
      for (var i = bpp; i < rowLength; i++) {
        out[r + i] = (out[r + i] + out[r + i - bpp]) & 0xFF;
      }
    }
    return out;
  }

  // PNG predictors: each row is prefixed with a filter-type byte.
  final rows = data.length ~/ (rowLength + 1);
  final out = Uint8List(rows * rowLength);
  final previous = Uint8List(rowLength);
  var src = 0;
  var dst = 0;
  for (var r = 0; r < rows; r++) {
    final type = data[src++];
    final row = Uint8List(rowLength);
    for (var i = 0; i < rowLength; i++) {
      row[i] = src < data.length ? data[src++] : 0;
    }
    for (var i = 0; i < rowLength; i++) {
      final left = i >= bpp ? row[i - bpp] : 0;
      final up = previous[i];
      final upLeft = i >= bpp ? previous[i - bpp] : 0;
      switch (type) {
        case 1:
          row[i] = (row[i] + left) & 0xFF;
        case 2:
          row[i] = (row[i] + up) & 0xFF;
        case 3:
          row[i] = (row[i] + ((left + up) >> 1)) & 0xFF;
        case 4:
          final p = left + up - upLeft;
          final pa = (p - left).abs();
          final pb = (p - up).abs();
          final pc = (p - upLeft).abs();
          final pred = (pa <= pb && pa <= pc) ? left : (pb <= pc ? up : upLeft);
          row[i] = (row[i] + pred) & 0xFF;
        default:
          break; // type 0: none
      }
    }
    out.setRange(dst, dst + rowLength, row);
    previous.setRange(0, rowLength, row);
    dst += rowLength;
  }
  return out;
}

Uint8List _asciiHexDecode(Uint8List data) {
  final out = <int>[];
  var high = -1;
  for (final c in data) {
    if (c == 0x3E) break; // '>'
    int v;
    if (c >= 0x30 && c <= 0x39) {
      v = c - 0x30;
    } else if (c >= 0x41 && c <= 0x46) {
      v = c - 0x41 + 10;
    } else if (c >= 0x61 && c <= 0x66) {
      v = c - 0x61 + 10;
    } else {
      continue;
    }
    if (high < 0) {
      high = v;
    } else {
      out.add(high * 16 + v);
      high = -1;
    }
  }
  if (high >= 0) out.add(high * 16);
  return Uint8List.fromList(out);
}

Uint8List _ascii85Decode(Uint8List data) {
  final out = <int>[];
  final group = <int>[];
  var i = 0;
  // An optional <~ introduces the data.
  if (data.length >= 2 && data[0] == 0x3C && data[1] == 0x7E) i = 2;
  for (; i < data.length; i++) {
    final c = data[i];
    if (c == 0x7E) break; // ~>
    if (c == 0x7A && group.isEmpty) {
      out.addAll(const <int>[0, 0, 0, 0]);
      continue;
    }
    if (c < 0x21 || c > 0x75) continue;
    group.add(c - 0x21);
    if (group.length == 5) {
      var value = 0;
      for (final g in group) {
        value = value * 85 + g;
      }
      out.addAll(<int>[
        (value >> 24) & 0xFF,
        (value >> 16) & 0xFF,
        (value >> 8) & 0xFF,
        value & 0xFF,
      ]);
      group.clear();
    }
  }
  if (group.isNotEmpty) {
    final n = group.length;
    while (group.length < 5) {
      group.add(84);
    }
    var value = 0;
    for (final g in group) {
      value = value * 85 + g;
    }
    final bytes = <int>[
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ];
    out.addAll(bytes.take(n - 1));
  }
  return Uint8List.fromList(out);
}

Uint8List _runLengthDecode(Uint8List data) {
  final out = <int>[];
  var i = 0;
  while (i < data.length) {
    final n = data[i++];
    if (n == 128) break;
    if (n < 128) {
      for (var k = 0; k <= n && i < data.length; k++) {
        out.add(data[i++]);
      }
    } else {
      if (i >= data.length) break;
      final b = data[i++];
      for (var k = 0; k < 257 - n; k++) {
        out.add(b);
      }
    }
  }
  return Uint8List.fromList(out);
}

Uint8List _lzwDecode(Uint8List data, int earlyChange) {
  final out = <int>[];
  var dict = <List<int>>[];
  void resetDict() {
    dict = List<List<int>>.generate(256, (i) => <int>[i])
      ..add(<int>[])
      ..add(<int>[]);
  }

  resetDict();
  var codeWidth = 9;
  var bitBuffer = 0;
  var bitCount = 0;
  List<int>? previous;

  for (final byte in data) {
    bitBuffer = (bitBuffer << 8) | byte;
    bitCount += 8;
    while (bitCount >= codeWidth) {
      final code =
          (bitBuffer >> (bitCount - codeWidth)) & ((1 << codeWidth) - 1);
      bitCount -= codeWidth;

      if (code == 256) {
        resetDict();
        codeWidth = 9;
        previous = null;
        continue;
      }
      if (code == 257) return Uint8List.fromList(out);

      List<int> entry;
      if (code < dict.length) {
        entry = dict[code];
      } else if (previous != null) {
        entry = <int>[...previous, previous.first];
      } else {
        return Uint8List.fromList(out);
      }
      out.addAll(entry);
      if (previous != null) dict.add(<int>[...previous, entry.first]);
      previous = entry;

      final limit = dict.length + earlyChange;
      if (limit >= 512 && codeWidth == 9) {
        codeWidth = 10;
      } else if (limit >= 1024 && codeWidth == 10) {
        codeWidth = 11;
      } else if (limit >= 2048 && codeWidth == 11) {
        codeWidth = 12;
      }
    }
  }
  return Uint8List.fromList(out);
}
