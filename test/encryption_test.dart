// Reading protected PDFs.
//
// The fixtures are encrypted by qpdf, not by this package, so these test the
// standard security handler as specified rather than a round trip through our
// own assumptions. Between them they cover every revision in the wild:
//
//   rc4-40.pdf          R2, RC4 40-bit
//   rc4-128.pdf         R3, RC4 128-bit
//   aes-128.pdf         R4, AESV2
//   aes-256.pdf         R6, AESV3
//   aes-256-userpw.pdf  R6, AESV3, and a user password that is required
//
// All but the last carry an owner password and an empty user password, which
// is how a government office publishes a document it does not want edited.
import 'dart:io';
import 'dart:typed_data';

import 'package:bangla_pdf/extract.dart';
import 'package:flutter_test/flutter_test.dart';

const expected = 'গণপ্রজাতন্ত্রী বাংলাদেশ সরকার';
const expectedSecondLine = 'ক্ষ্ম কর্ম';

String flatten(String s) =>
    s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' ');

Uint8List fixture(String name) => Uint8List.fromList(
      File('test/fixtures/encrypted/$name').readAsBytesSync(),
    );

void main() {
  group('documents protected with an empty user password', () {
    const files = <String, String>{
      'rc4-40.pdf': 'revision 2, RC4 40-bit',
      'rc4-128.pdf': 'revision 3, RC4 128-bit',
      'aes-128.pdf': 'revision 4, AES-128',
      'aes-256.pdf': 'revision 6, AES-256',
    };

    for (final entry in files.entries) {
      test('${entry.value} is read as if it were not protected', () {
        final result = BanglaPdfExtractor.extract(fixture(entry.key));

        expect(result.isEncrypted, isTrue, reason: entry.key);
        expect(result.isLocked, isFalse, reason: entry.key);
        expect(flatten(result.text), contains(expected), reason: entry.key);
        expect(
          flatten(result.text),
          contains(expectedSecondLine),
          reason: entry.key,
        );
        expect(result.encodingDetected, BanglaTextEncoding.unicode);
      });
    }
  });

  group('a document that really does need a password', () {
    test('without one, it reports being locked rather than guessing', () {
      final result = BanglaPdfExtractor.extract(fixture('aes-256-userpw.pdf'));
      expect(result.isEncrypted, isTrue);
      expect(result.isLocked, isTrue);
      expect(result.text, isEmpty);
    });

    test('with the user password, it reads', () {
      final result = BanglaPdfExtractor.extract(
        fixture('aes-256-userpw.pdf'),
        password: 'pass123',
      );
      expect(result.isLocked, isFalse);
      expect(flatten(result.text), contains(expected));
    });

    test('with the owner password, it reads too', () {
      // A document opens on either password; the owner one is what a
      // publisher sets to stop editing.
      final result = BanglaPdfExtractor.extract(
        fixture('aes-256-userpw.pdf'),
        password: 'secret',
      );
      expect(result.isLocked, isFalse);
      expect(flatten(result.text), contains(expected));
    });

    test('a wrong password does not half-open the document', () {
      final result = BanglaPdfExtractor.extract(
        fixture('aes-256-userpw.pdf'),
        password: 'not-it',
      );
      expect(result.isLocked, isTrue);
      expect(result.text, isEmpty);
    });
  });

  test('an unprotected document is unaffected', () {
    // Guards the obvious regression: decryption must not touch a plain file.
    final plain = BanglaPdfExtractor.extract(fixture('../pdfs/invoice-1.pdf'));
    expect(plain.isEncrypted, isFalse);
    expect(plain.isLocked, isFalse);
    expect(plain.text, isNotEmpty);
  });
}
