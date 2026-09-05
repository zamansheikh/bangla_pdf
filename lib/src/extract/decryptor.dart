/// The PDF standard security handler, for reading protected documents.
///
/// Most "protected" PDFs — the kind a government office publishes — carry an
/// owner password to discourage editing and an *empty* user password, so they
/// open without being asked for anything. The bytes are still encrypted, and
/// an extractor that ignores that reads noise. This decrypts them.
///
/// Every revision in the wild is covered: RC4 (revisions 2 and 3), AES-128
/// (revision 4) and AES-256 (revisions 5 and 6).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:bangla_pdf/src/extract/crypt.dart';
import 'package:bangla_pdf/src/extract/pdf_object.dart';
import 'package:crypto/crypto.dart' as c;

/// How a particular string or stream is protected.
enum _Cipher { none, rc4, aesV2, aesV3 }

/// The 32-byte string a PDF pads short passwords with, from the spec.
const List<int> _pad = <int>[
  0x28, 0xBF, 0x4E, 0x5E, 0x4E, 0x75, 0x8A, 0x41, //
  0x64, 0x00, 0x4E, 0x56, 0xFF, 0xFA, 0x01, 0x08,
  0x2E, 0x2E, 0x00, 0xB6, 0xD0, 0x68, 0x3E, 0x80,
  0x2F, 0x0C, 0xA9, 0xFE, 0x64, 0x53, 0x69, 0x7A,
];

/// Decrypts the strings and streams of one document.
class PdfDecryptor {
  PdfDecryptor._(this._key, this._streamCipher, this._stringCipher);

  /// Builds a decryptor for [encrypt], or `null` when the document cannot be
  /// opened with [password] — a real owner-password-only document, or a
  /// handler this does not implement.
  ///
  /// [resolve] reads an indirect value out of the encryption dictionary, and
  /// [firstFileId] is the first element of the trailer's `/ID`.
  static PdfDecryptor? open(
    PdfDictObj encrypt,
    PdfObj Function(PdfObj) resolve, {
    required Uint8List firstFileId,
    String password = '',
  }) {
    final filter = resolve(encrypt['Filter']);
    if (filter is! PdfNameObj || filter.value != 'Standard') return null;

    int intOf(String key, int fallback) {
      final value = resolve(encrypt[key]);
      return value is PdfNumObj ? value.asInt : fallback;
    }

    Uint8List bytesOf(String key) {
      final value = resolve(encrypt[key]);
      return value is PdfStringObj ? value.bytes : Uint8List(0);
    }

    final v = intOf('V', 0);
    final r = intOf('R', 0);
    final o = bytesOf('O');
    final u = bytesOf('U');
    final permissions = intOf('P', -1);
    var lengthBits = intOf('Length', 40);

    // V4 and V5 name their ciphers in a crypt-filter dictionary.
    var streamCipher = v >= 4 ? _Cipher.none : _Cipher.rc4;
    var stringCipher = streamCipher;
    if (v >= 4) {
      final cf = resolve(encrypt['CF']);
      String filterName(String key) {
        final value = resolve(encrypt[key]);
        return value is PdfNameObj ? value.value : 'Identity';
      }

      _Cipher cipherFor(String name) {
        if (name == 'Identity') return _Cipher.none;
        if (cf is! PdfDictObj) return _Cipher.none;
        final entry = resolve(cf[name]);
        if (entry is! PdfDictObj) return _Cipher.none;
        final method = resolve(entry['CFM']);
        final bits = resolve(entry['Length']);
        if (bits is PdfNumObj && bits.asInt > 0) {
          // Some writers give bytes here and some give bits.
          lengthBits = bits.asInt <= 64 ? bits.asInt * 8 : bits.asInt;
        }
        if (method is! PdfNameObj) return _Cipher.none;
        return switch (method.value) {
          'V2' => _Cipher.rc4,
          'AESV2' => _Cipher.aesV2,
          'AESV3' => _Cipher.aesV3,
          _ => _Cipher.none,
        };
      }

      streamCipher = cipherFor(filterName('StmF'));
      stringCipher = cipherFor(filterName('StrF'));
    }

    final Uint8List? key;
    if (r >= 5) {
      key = _keyForRevision6(password, u, bytesOf('UE'), o, bytesOf('OE'));
      streamCipher = _Cipher.aesV3;
      stringCipher = _Cipher.aesV3;
    } else {
      key = _keyForRevision2to4(
        password: password,
        ownerEntry: o,
        permissions: permissions,
        fileId: firstFileId,
        revision: r,
        lengthBits: lengthBits,
        encryptMetadata: switch (resolve(encrypt['EncryptMetadata'])) {
          final PdfBoolObj b => b.value,
          _ => true,
        },
      );
    }
    if (key == null) return null;
    return PdfDecryptor._(key, streamCipher, stringCipher);
  }

  final Uint8List _key;
  final _Cipher _streamCipher;
  final _Cipher _stringCipher;

  /// Decrypts a stream belonging to object [number] generation [generation].
  Uint8List decryptStream(Uint8List data, int number, int generation) =>
      _apply(_streamCipher, data, number, generation);

  /// Decrypts a string belonging to object [number] generation [generation].
  Uint8List decryptString(Uint8List data, int number, int generation) =>
      _apply(_stringCipher, data, number, generation);

  Uint8List _apply(_Cipher cipher, Uint8List data, int number, int generation) {
    switch (cipher) {
      case _Cipher.none:
        return data;
      case _Cipher.aesV3:
        // AES-256 uses the file key as it is; there is no per-object key.
        return aesCbcDecrypt(_key, data);
      case _Cipher.rc4:
        return rc4(_objectKey(number, generation, aes: false), data);
      case _Cipher.aesV2:
        return aesCbcDecrypt(_objectKey(number, generation, aes: true), data);
    }
  }

  /// Algorithm 1: mixes the object and generation numbers into the file key,
  /// so every object is encrypted differently.
  Uint8List _objectKey(int number, int generation, {required bool aes}) {
    final input = BytesBuilder(copy: false)
      ..add(_key)
      ..add(<int>[
        number & 0xFF,
        (number >> 8) & 0xFF,
        (number >> 16) & 0xFF,
        generation & 0xFF,
        (generation >> 8) & 0xFF,
      ]);
    // AES-128 adds a fixed salt, so the same object gets a different key than
    // it would under RC4.
    if (aes) input.add(<int>[0x73, 0x41, 0x6C, 0x54]); // "sAlT"

    final digest = Uint8List.fromList(c.md5.convert(input.takeBytes()).bytes);
    final length = _key.length + 5;
    return Uint8List.sublistView(digest, 0, length > 16 ? 16 : length);
  }
}

/// Algorithm 2: the file key for revisions 2 to 4.
Uint8List? _keyForRevision2to4({
  required String password,
  required Uint8List ownerEntry,
  required int permissions,
  required Uint8List fileId,
  required int revision,
  required int lengthBits,
  required bool encryptMetadata,
}) {
  final bytes = latin1.encode(password);
  final padded = Uint8List(32);
  final take = bytes.length > 32 ? 32 : bytes.length;
  padded.setRange(0, take, bytes);
  padded.setRange(take, 32, _pad);

  final input = BytesBuilder(copy: false)
    ..add(padded)
    ..add(ownerEntry)
    ..add(<int>[
      permissions & 0xFF,
      (permissions >> 8) & 0xFF,
      (permissions >> 16) & 0xFF,
      (permissions >> 24) & 0xFF,
    ])
    ..add(fileId);
  if (revision >= 4 && !encryptMetadata) {
    input.add(<int>[0xFF, 0xFF, 0xFF, 0xFF]);
  }

  var digest = Uint8List.fromList(c.md5.convert(input.takeBytes()).bytes);
  final length = revision == 2 ? 5 : (lengthBits ~/ 8).clamp(5, 16);
  if (revision >= 3) {
    // Deliberately slow: 50 more rounds over the first `length` bytes.
    for (var i = 0; i < 50; i++) {
      digest = Uint8List.fromList(
        c.md5.convert(Uint8List.sublistView(digest, 0, length)).bytes,
      );
    }
  }
  return Uint8List.sublistView(digest, 0, length);
}

/// Algorithm 2.A: the file key for revisions 5 and 6, AES-256.
///
/// The user password is tried first, then the owner password, which is how a
/// document with an owner password and an empty user password opens.
Uint8List? _keyForRevision6(
  String password,
  Uint8List u,
  Uint8List ue,
  Uint8List o,
  Uint8List oe,
) {
  if (u.length < 48) return null;
  final bytes = latin1.encode(password);

  Uint8List? tryUser() {
    final validation = Uint8List.sublistView(u, 32, 40);
    final keySalt = Uint8List.sublistView(u, 40, 48);
    final check = _hash2B(bytes, validation, Uint8List(0));
    if (!_same(check, Uint8List.sublistView(u, 0, 32))) return null;
    if (ue.length < 32) return null;
    final intermediate = _hash2B(bytes, keySalt, Uint8List(0));
    return aesCbcNoPadDecryptZeroIv(
      intermediate,
      Uint8List.sublistView(ue, 0, 32),
    );
  }

  Uint8List? tryOwner() {
    if (o.length < 48 || oe.length < 32) return null;
    final first48 = Uint8List.sublistView(u, 0, 48);
    final validation = Uint8List.sublistView(o, 32, 40);
    final keySalt = Uint8List.sublistView(o, 40, 48);
    final check = _hash2B(bytes, validation, first48);
    if (!_same(check, Uint8List.sublistView(o, 0, 32))) return null;
    final intermediate = _hash2B(bytes, keySalt, first48);
    return aesCbcNoPadDecryptZeroIv(
      intermediate,
      Uint8List.sublistView(oe, 0, 32),
    );
  }

  return tryUser() ?? tryOwner();
}

/// Algorithm 2.B: the deliberately expensive hash revisions 5 and 6 use.
///
/// Revision 5 stopped at a single SHA-256; revision 6 added the loop below to
/// make guessing passwords costly. Running the loop for a revision 5 document
/// is harmless, because it exits immediately when the first round agrees.
Uint8List _hash2B(Uint8List password, Uint8List salt, Uint8List userData) {
  var k = Uint8List.fromList(
    c.sha256.convert(<int>[...password, ...salt, ...userData]).bytes,
  );

  for (var round = 0;; round++) {
    final block = <int>[...password, ...k, ...userData];
    final k1 = BytesBuilder(copy: false);
    for (var i = 0; i < 64; i++) {
      k1.add(block);
    }
    final e = aesCbcNoPadEncrypt(
      Uint8List.sublistView(k, 0, 16),
      Uint8List.sublistView(k, 16, 32),
      k1.takeBytes(),
    );
    if (e.isEmpty) return k;

    var sum = 0;
    for (var i = 0; i < 16 && i < e.length; i++) {
      sum += e[i];
    }
    k = Uint8List.fromList(
      switch (sum % 3) {
        0 => c.sha256.convert(e).bytes,
        1 => c.sha384.convert(e).bytes,
        _ => c.sha512.convert(e).bytes,
      },
    );

    if (round >= 63 && e.isNotEmpty && e[e.length - 1] <= round - 31) break;
    if (round > 256) break; // never seen in practice; bounds a bad file
  }
  return Uint8List.sublistView(k, 0, 32);
}

bool _same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
