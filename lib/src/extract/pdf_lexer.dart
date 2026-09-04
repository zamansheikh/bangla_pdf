/// A tokenizer for PDF syntax, shared by the file parser and the content-stream
/// walker.
///
/// It never throws: a malformed document yields whatever objects could be read
/// and stops. Extraction is best-effort by nature — the PDFs that most need it
/// are the ones produced by the worst tools.
library;

import 'dart:typed_data';

import 'package:bangla_pdf/src/extract/pdf_object.dart';

/// Character classification per PDF 32000-1 §7.2.2.
bool _isWhitespace(int c) =>
    c == 0x00 || c == 0x09 || c == 0x0A || c == 0x0C || c == 0x0D || c == 0x20;

bool _isDelimiter(int c) =>
    c == 0x28 || // (
    c == 0x29 || // )
    c == 0x3C || // <
    c == 0x3E || // >
    c == 0x5B || // [
    c == 0x5D || // ]
    c == 0x7B || // {
    c == 0x7D || // }
    c == 0x2F || // /
    c == 0x25; // %

bool _isRegular(int c) => !_isWhitespace(c) && !_isDelimiter(c);

int _hexValue(int c) {
  if (c >= 0x30 && c <= 0x39) return c - 0x30;
  if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10;
  if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10;
  return -1;
}

/// Reads PDF objects out of a byte buffer.
class PdfLexer {
  PdfLexer(this.bytes, [this.offset = 0]);

  final Uint8List bytes;

  /// Current read position.
  int offset;

  bool get atEnd => offset >= bytes.length;

  int get _current => offset < bytes.length ? bytes[offset] : -1;

  /// Skips whitespace and `%` comments.
  void skipWhitespace() {
    while (offset < bytes.length) {
      final c = bytes[offset];
      if (_isWhitespace(c)) {
        offset++;
      } else if (c == 0x25) {
        while (offset < bytes.length &&
            bytes[offset] != 0x0A &&
            bytes[offset] != 0x0D) {
          offset++;
        }
      } else {
        return;
      }
    }
  }

  /// Reads the next token as a [PdfObj], or `null` at end of input.
  ///
  /// Indirect references (`1 0 R`) are recognised by lookahead. `obj`,
  /// `endobj`, `stream` and content operators come back as [PdfOperatorObj].
  PdfObj? next() {
    skipWhitespace();
    if (atEnd) return null;
    final c = _current;

    switch (c) {
      case 0x2F: // /
        return PdfNameObj(_readName());
      case 0x28: // (
        return PdfStringObj(_readLiteralString());
      case 0x5B: // [
        offset++;
        return PdfArrayObj(_readUntil(0x5D));
      case 0x5D: // ]
        offset++;
        return const PdfOperatorObj(']');
      case 0x3C: // < or <<
        if (offset + 1 < bytes.length && bytes[offset + 1] == 0x3C) {
          offset += 2;
          return _readDict();
        }
        return PdfStringObj(_readHexString());
      case 0x3E: // >>
        offset +=
            (offset + 1 < bytes.length && bytes[offset + 1] == 0x3E) ? 2 : 1;
        return const PdfOperatorObj('>>');
      case 0x7B: // {
      case 0x7D: // }
        offset++;
        return PdfOperatorObj(String.fromCharCode(c));
    }

    final token = _readToken();
    if (token.isEmpty) {
      offset++;
      return const PdfNullObj();
    }
    switch (token) {
      case 'true':
        return const PdfBoolObj(true);
      case 'false':
        return const PdfBoolObj(false);
      case 'null':
        return const PdfNullObj();
    }

    final number = double.tryParse(token);
    if (number == null) return PdfOperatorObj(token);

    // `n g R` is an indirect reference; `n g obj` starts an object. Both need
    // two-token lookahead, so the position is restored when it is neither.
    if (number == number.roundToDouble() && number >= 0) {
      final save = offset;
      skipWhitespace();
      final genStart = offset;
      final genToken = _readToken();
      final gen = int.tryParse(genToken);
      if (gen != null && gen >= 0) {
        skipWhitespace();
        final kwStart = offset;
        final keyword = _readToken();
        if (keyword == 'R') {
          return PdfRefObj(number.toInt(), gen);
        }
        offset = kwStart;
      }
      offset = genStart == offset ? save : save;
    }
    return PdfNumObj(number);
  }

  /// Reads objects until [closer] or end of input.
  List<PdfObj> _readUntil(int closer) {
    final out = <PdfObj>[];
    var guard = 0;
    while (!atEnd && ++guard < 1000000) {
      skipWhitespace();
      if (_current == closer) {
        offset++;
        break;
      }
      final o = next();
      if (o == null) break;
      if (o is PdfOperatorObj && o.name == String.fromCharCode(closer)) break;
      out.add(o);
    }
    return out;
  }

  PdfDictObj _readDict() {
    final map = <String, PdfObj>{};
    var guard = 0;
    while (!atEnd && ++guard < 1000000) {
      skipWhitespace();
      if (_current == 0x3E) {
        offset +=
            (offset + 1 < bytes.length && bytes[offset + 1] == 0x3E) ? 2 : 1;
        break;
      }
      if (_current != 0x2F) {
        // Not a name where a key must be: skip a token and keep going rather
        // than abandoning the whole dictionary.
        final o = next();
        if (o == null) break;
        continue;
      }
      final key = _readName();
      final value = next();
      if (value == null) break;
      if (value is PdfOperatorObj && value.name == '>>') break;
      map[key] = value;
    }
    return PdfDictObj(map);
  }

  String _readName() {
    offset++; // skip '/'
    final out = <int>[];
    while (offset < bytes.length && _isRegular(bytes[offset])) {
      var c = bytes[offset++];
      if (c == 0x23 && offset + 1 < bytes.length) {
        final hi = _hexValue(bytes[offset]);
        final lo = _hexValue(bytes[offset + 1]);
        if (hi >= 0 && lo >= 0) {
          c = hi * 16 + lo;
          offset += 2;
        }
      }
      out.add(c);
    }
    return String.fromCharCodes(out);
  }

  String _readToken() {
    final start = offset;
    while (offset < bytes.length && _isRegular(bytes[offset])) {
      offset++;
    }
    return String.fromCharCodes(bytes.sublist(start, offset));
  }

  Uint8List _readLiteralString() {
    offset++; // skip '('
    final out = <int>[];
    var depth = 1;
    while (offset < bytes.length) {
      var c = bytes[offset++];
      if (c == 0x5C) {
        // backslash
        if (offset >= bytes.length) break;
        c = bytes[offset++];
        switch (c) {
          case 0x6E:
            out.add(0x0A);
          case 0x72:
            out.add(0x0D);
          case 0x74:
            out.add(0x09);
          case 0x62:
            out.add(0x08);
          case 0x66:
            out.add(0x0C);
          case 0x0A:
            break; // line continuation
          case 0x0D:
            if (offset < bytes.length && bytes[offset] == 0x0A) offset++;
          default:
            if (c >= 0x30 && c <= 0x37) {
              var value = c - 0x30;
              for (var i = 0; i < 2; i++) {
                if (offset < bytes.length &&
                    bytes[offset] >= 0x30 &&
                    bytes[offset] <= 0x37) {
                  value = value * 8 + (bytes[offset++] - 0x30);
                } else {
                  break;
                }
              }
              out.add(value & 0xFF);
            } else {
              out.add(c);
            }
        }
        continue;
      }
      if (c == 0x28) depth++;
      if (c == 0x29) {
        depth--;
        if (depth == 0) break;
      }
      out.add(c);
    }
    return Uint8List.fromList(out);
  }

  Uint8List _readHexString() {
    offset++; // skip '<'
    final out = <int>[];
    var high = -1;
    while (offset < bytes.length) {
      final c = bytes[offset++];
      if (c == 0x3E) break;
      final v = _hexValue(c);
      if (v < 0) continue;
      if (high < 0) {
        high = v;
      } else {
        out.add(high * 16 + v);
        high = -1;
      }
    }
    // An odd number of digits is padded with a trailing zero.
    if (high >= 0) out.add(high * 16);
    return Uint8List.fromList(out);
  }
}
