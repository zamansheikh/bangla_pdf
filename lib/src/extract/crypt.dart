/// The ciphers a PDF's standard security handler uses.
///
/// RC4 is a few lines; AES needs its inverse cipher, which is why this file
/// exists rather than a dependency. `package:crypto` supplies MD5 and SHA-2,
/// and is already in the tree, but has no block ciphers.
///
/// Decryption only: nothing here is used to protect anything.
library;

import 'dart:typed_data';

/// RC4, which is its own inverse.
Uint8List rc4(Uint8List key, Uint8List data) {
  if (key.isEmpty) return Uint8List.fromList(data);
  final s = Uint8List(256);
  for (var i = 0; i < 256; i++) {
    s[i] = i;
  }
  var j = 0;
  for (var i = 0; i < 256; i++) {
    j = (j + s[i] + key[i % key.length]) & 0xFF;
    final t = s[i];
    s[i] = s[j];
    s[j] = t;
  }

  final out = Uint8List(data.length);
  var x = 0;
  var y = 0;
  for (var n = 0; n < data.length; n++) {
    x = (x + 1) & 0xFF;
    y = (y + s[x]) & 0xFF;
    final t = s[x];
    s[x] = s[y];
    s[y] = t;
    out[n] = data[n] ^ s[(s[x] + s[y]) & 0xFF];
  }
  return out;
}

/// Decrypts [data] with AES in CBC mode, taking the IV from the first block.
///
/// This is how a PDF stores an encrypted string or stream. Returns an empty
/// list when the input is too short or not a whole number of blocks.
Uint8List aesCbcDecrypt(Uint8List key, Uint8List data) {
  if (data.length < 32 || data.length % 16 != 0) return Uint8List(0);
  final aes = _Aes(key);
  final out = BytesBuilder(copy: false);
  var previous = Uint8List.sublistView(data, 0, 16);

  for (var at = 16; at < data.length; at += 16) {
    final block = Uint8List.sublistView(data, at, at + 16);
    final plain = aes.decryptBlock(block);
    for (var i = 0; i < 16; i++) {
      plain[i] ^= previous[i];
    }
    out.add(plain);
    previous = block;
  }

  final bytes = out.takeBytes();
  // PKCS#7: the last byte says how many were added.
  if (bytes.isEmpty) return bytes;
  final pad = bytes.last;
  if (pad < 1 || pad > 16 || pad > bytes.length) return bytes;
  return Uint8List.sublistView(bytes, 0, bytes.length - pad);
}

/// Decrypts [data] with AES in ECB mode and no padding.
///
/// Used only by the revision 6 password check, which encrypts a fixed 16-byte
/// block rather than a message.
Uint8List aesEcbNoPadDecrypt(Uint8List key, Uint8List data) {
  final aes = _Aes(key);
  final out = Uint8List(data.length - data.length % 16);
  for (var at = 0; at + 16 <= data.length; at += 16) {
    out.setRange(
      at,
      at + 16,
      aes.decryptBlock(Uint8List.sublistView(data, at, at + 16)),
    );
  }
  return out;
}

/// Decrypts [data] with AES-CBC, a zero IV and no padding.
///
/// How revisions 5 and 6 wrap the file key in `/UE` and `/OE`.
Uint8List aesCbcNoPadDecryptZeroIv(Uint8List key, Uint8List data) {
  final aes = _Aes(key);
  final out = Uint8List(data.length - data.length % 16);
  var previous = Uint8List(16);
  for (var at = 0; at + 16 <= data.length; at += 16) {
    final block = Uint8List.sublistView(data, at, at + 16);
    final plain = aes.decryptBlock(block);
    for (var i = 0; i < 16; i++) {
      plain[i] ^= previous[i];
    }
    out.setRange(at, at + 16, plain);
    previous = Uint8List.fromList(block);
  }
  return out;
}

/// Encrypts [data] with AES-CBC and no padding, given an explicit [iv].
///
/// Revision 6 derives its key by repeatedly *encrypting*, so the forward
/// direction is needed too.
Uint8List aesCbcNoPadEncrypt(Uint8List key, Uint8List iv, Uint8List data) {
  final aes = _Aes(key);
  final out = Uint8List(data.length - data.length % 16);
  var previous = Uint8List.fromList(iv);
  for (var at = 0; at + 16 <= data.length; at += 16) {
    final block = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      block[i] = data[at + i] ^ previous[i];
    }
    final cipher = aes.encryptBlock(block);
    out.setRange(at, at + 16, cipher);
    previous = cipher;
  }
  return out;
}

/// AES-128, 192 and 256, enough to decrypt a PDF.
class _Aes {
  _Aes(Uint8List key) : _rounds = key.length ~/ 4 + 6 {
    _expandKey(key);
  }

  final int _rounds;
  late final List<Uint8List> _roundKeys;

  static final Uint8List _sbox = _buildSbox();
  static final Uint8List _inv = _buildInverseSbox();

  static Uint8List _buildSbox() {
    // Generated rather than tabulated: the S-box is the multiplicative inverse
    // in GF(2^8) followed by an affine transform, and 256 magic bytes in a
    // source file are harder to check than the four lines that make them.
    final out = Uint8List(256);
    var p = 1;
    var q = 1;
    do {
      p = p ^ ((p << 1) & 0xFF) ^ ((p & 0x80) != 0 ? 0x1B : 0);
      q ^= q << 1;
      q ^= q << 2;
      q ^= q << 4;
      q &= 0xFF;
      if ((q & 0x80) != 0) q ^= 0x09;
      final value = q ^ _rotl(q, 1) ^ _rotl(q, 2) ^ _rotl(q, 3) ^ _rotl(q, 4);
      out[p] = (value ^ 0x63) & 0xFF;
    } while (p != 1);
    out[0] = 0x63;
    return out;
  }

  static Uint8List _buildInverseSbox() {
    final out = Uint8List(256);
    for (var i = 0; i < 256; i++) {
      out[_sbox[i]] = i;
    }
    return out;
  }

  static int _rotl(int x, int shift) =>
      ((x << shift) | (x >> (8 - shift))) & 0xFF;

  /// Multiplication in GF(2^8) with the AES polynomial.
  static int _mul(int a, int b) {
    var result = 0;
    var x = a;
    var y = b;
    while (y != 0) {
      if ((y & 1) != 0) result ^= x;
      final high = x & 0x80;
      x = (x << 1) & 0xFF;
      if (high != 0) x ^= 0x1B;
      y >>= 1;
    }
    return result;
  }

  void _expandKey(Uint8List key) {
    final words = <Uint8List>[];
    for (var i = 0; i < key.length ~/ 4; i++) {
      words.add(Uint8List.fromList(key.sublist(i * 4, i * 4 + 4)));
    }
    final nk = key.length ~/ 4;
    final total = 4 * (_rounds + 1);
    var rcon = 1;
    for (var i = nk; i < total; i++) {
      final temp = Uint8List.fromList(words[i - 1]);
      if (i % nk == 0) {
        final t = temp[0];
        temp[0] = _sbox[temp[1]] ^ rcon;
        temp[1] = _sbox[temp[2]];
        temp[2] = _sbox[temp[3]];
        temp[3] = _sbox[t];
        rcon = _mul(rcon, 2);
      } else if (nk > 6 && i % nk == 4) {
        for (var k = 0; k < 4; k++) {
          temp[k] = _sbox[temp[k]];
        }
      }
      final word = Uint8List(4);
      for (var k = 0; k < 4; k++) {
        word[k] = words[i - nk][k] ^ temp[k];
      }
      words.add(word);
    }

    _roundKeys = <Uint8List>[
      for (var r = 0; r <= _rounds; r++)
        Uint8List.fromList(<int>[
          for (var w = 0; w < 4; w++) ...words[r * 4 + w],
        ]),
    ];
  }

  void _addRoundKey(Uint8List state, int round) {
    final key = _roundKeys[round];
    for (var i = 0; i < 16; i++) {
      state[i] ^= key[i];
    }
  }

  Uint8List encryptBlock(Uint8List input) {
    final state = Uint8List.fromList(input);
    _addRoundKey(state, 0);
    for (var round = 1; round <= _rounds; round++) {
      for (var i = 0; i < 16; i++) {
        state[i] = _sbox[state[i]];
      }
      _shiftRows(state, inverse: false);
      if (round != _rounds) _mixColumns(state, inverse: false);
      _addRoundKey(state, round);
    }
    return state;
  }

  Uint8List decryptBlock(Uint8List input) {
    final state = Uint8List.fromList(input);
    _addRoundKey(state, _rounds);
    for (var round = _rounds - 1; round >= 0; round--) {
      _shiftRows(state, inverse: true);
      for (var i = 0; i < 16; i++) {
        state[i] = _inv[state[i]];
      }
      _addRoundKey(state, round);
      if (round != 0) _mixColumns(state, inverse: true);
    }
    return state;
  }

  static void _shiftRows(Uint8List s, {required bool inverse}) {
    final copy = Uint8List.fromList(s);
    for (var row = 1; row < 4; row++) {
      for (var col = 0; col < 4; col++) {
        final from = inverse ? (col - row) % 4 : (col + row) % 4;
        s[col * 4 + row] = copy[((from + 4) % 4) * 4 + row];
      }
    }
  }

  static void _mixColumns(Uint8List s, {required bool inverse}) {
    const forward = <int>[2, 3, 1, 1];
    const backward = <int>[14, 11, 13, 9];
    final m = inverse ? backward : forward;
    for (var col = 0; col < 4; col++) {
      final a = <int>[
        s[col * 4],
        s[col * 4 + 1],
        s[col * 4 + 2],
        s[col * 4 + 3],
      ];
      for (var row = 0; row < 4; row++) {
        var value = 0;
        for (var k = 0; k < 4; k++) {
          value ^= _mul(a[k], m[(k - row + 4) % 4]);
        }
        s[col * 4 + row] = value;
      }
    }
  }
}
