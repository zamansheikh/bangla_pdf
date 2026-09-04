/// Reads a PDF file: cross-reference tables and streams, indirect objects,
/// object streams, and the page tree.
///
/// Designed to survive damage. If the cross-reference table is missing, wrong
/// or points into the wrong place — which is common in the scanned and
/// government documents this package exists for — the reader falls back to
/// scanning the whole file for `n g obj` markers.
library;

import 'dart:typed_data';

import 'package:bangla_pdf/src/extract/filters.dart';
import 'package:bangla_pdf/src/extract/pdf_lexer.dart';
import 'package:bangla_pdf/src/extract/pdf_object.dart';

/// A parsed PDF document.
class PdfReader {
  PdfReader._(this.bytes);

  /// Parses [bytes]. Returns `null` only when the data is not a PDF at all.
  static PdfReader? open(Uint8List bytes) {
    if (bytes.length < 8) return null;
    final header = String.fromCharCodes(
      bytes.sublist(0, bytes.length < 1024 ? bytes.length : 1024),
    );
    if (!header.contains('%PDF-')) return null;
    final reader = PdfReader._(bytes).._load();
    return reader;
  }

  final Uint8List bytes;

  /// Object number -> byte offset of `n g obj`.
  final Map<int, int> _offsets = <int, int>{};

  /// Object number -> (object stream number, index within it).
  final Map<int, (int, int)> _compressed = <int, (int, int)>{};

  final Map<int, PdfObj> _cache = <int, PdfObj>{};
  final Set<int> _loading = <int>{};

  /// The trailer dictionary, merged across every cross-reference section.
  PdfDictObj trailer = const PdfDictObj(<String, PdfObj>{});

  /// Whether the document declares encryption, which this reader does not
  /// decrypt.
  bool get isEncrypted => trailer.has('Encrypt');

  void _load() {
    try {
      _readXref();
    } catch (_) {
      // Ignored: the brute-force scan below is the recovery path.
    }
    // Always index by scanning too. It costs one pass and repairs documents
    // whose xref offsets are stale, which is common after naive editing.
    _scanForObjects();
    if (!trailer.has('Root')) _findRootByScan();
  }

  // --- cross-reference ------------------------------------------------------

  void _readXref() {
    final tail = String.fromCharCodes(
      bytes.sublist(bytes.length > 2048 ? bytes.length - 2048 : 0),
    );
    final marker = tail.lastIndexOf('startxref');
    if (marker < 0) return;
    final lexer = PdfLexer(
      bytes,
      (bytes.length > 2048 ? bytes.length - 2048 : 0) + marker + 9,
    );
    final start = lexer.next();
    if (start is! PdfNumObj) return;

    var offset = start.asInt;
    final seen = <int>{};
    while (offset > 0 && offset < bytes.length && seen.add(offset)) {
      final next = _readXrefSection(offset);
      if (next == null) break;
      offset = next;
    }
  }

  /// Reads one xref section, returning the `/Prev` offset if there is one.
  int? _readXrefSection(int offset) {
    final lexer = PdfLexer(bytes, offset)..skipWhitespace();
    final first = lexer.next();

    if (first is PdfOperatorObj && first.name == 'xref') {
      // Classic table.
      while (true) {
        lexer.skipWhitespace();
        final a = lexer.next();
        if (a is PdfOperatorObj && a.name == 'trailer') break;
        if (a is! PdfNumObj) return null;
        final b = lexer.next();
        if (b is! PdfNumObj) return null;
        final startNum = a.asInt;
        final count = b.asInt;
        for (var i = 0; i < count; i++) {
          lexer.skipWhitespace();
          final o = lexer.next();
          final g = lexer.next();
          final type = lexer.next();
          if (o is! PdfNumObj || g is! PdfNumObj) return null;
          final inUse = type is PdfOperatorObj && type.name == 'n';
          if (inUse) _offsets.putIfAbsent(startNum + i, () => o.asInt);
        }
      }
      final dict = lexer.next();
      if (dict is PdfDictObj) {
        _mergeTrailer(dict);
        // A hybrid file points at an xref stream holding the rest.
        final hybrid = dict['XRefStm'];
        if (hybrid is PdfNumObj) _readXrefSection(hybrid.asInt);
        final prev = dict['Prev'];
        if (prev is PdfNumObj) return prev.asInt;
      }
      return null;
    }

    // Cross-reference stream: `n g obj << … >> stream`.
    if (first is PdfNumObj) {
      lexer.next(); // generation
      final kw = lexer.next();
      if (kw is! PdfOperatorObj || kw.name != 'obj') return null;
      final obj = _readObjectBody(lexer);
      if (obj is! PdfStreamObj) return null;
      _readXrefStream(obj);
      _mergeTrailer(obj.dict);
      final prev = obj.dict['Prev'];
      if (prev is PdfNumObj) return prev.asInt;
    }
    return null;
  }

  void _readXrefStream(PdfStreamObj stream) {
    final data = decodeStream(stream.raw, stream.dict, _resolveShallow);
    if (data == null) return;
    final w = _resolveShallow(stream.dict['W']);
    if (w is! PdfArrayObj || w.length < 3) return;
    final widths = <int>[
      for (final v in w.values)
        if (v is PdfNumObj) v.asInt else 0,
    ];
    final rowLength = widths.fold<int>(0, (a, b) => a + b);
    if (rowLength <= 0) return;

    final ranges = <(int, int)>[];
    final index = _resolveShallow(stream.dict['Index']);
    if (index is PdfArrayObj) {
      for (var i = 0; i + 1 < index.length; i += 2) {
        final a = index[i];
        final b = index[i + 1];
        if (a is PdfNumObj && b is PdfNumObj) ranges.add((a.asInt, b.asInt));
      }
    } else {
      final size = _resolveShallow(stream.dict['Size']);
      ranges.add((0, size is PdfNumObj ? size.asInt : 0));
    }

    var pos = 0;
    int field(int width, int fallback) {
      if (width == 0) return fallback;
      var v = 0;
      for (var i = 0; i < width; i++) {
        v = (v << 8) | (pos < data.length ? data[pos++] : 0);
      }
      return v;
    }

    for (final (start, count) in ranges) {
      for (var i = 0; i < count; i++) {
        if (pos + rowLength > data.length) return;
        final type = field(widths[0], 1);
        final f2 = field(widths[1], 0);
        final f3 = field(widths[2], 0);
        final number = start + i;
        if (type == 1) {
          _offsets.putIfAbsent(number, () => f2);
        } else if (type == 2) {
          _compressed.putIfAbsent(number, () => (f2, f3));
        }
      }
    }
  }

  void _mergeTrailer(PdfDictObj dict) {
    final merged = <String, PdfObj>{...dict.entries, ...trailer.entries};
    trailer = PdfDictObj(merged);
  }

  // --- brute-force recovery -------------------------------------------------

  /// Indexes every `n g obj` in the file.
  ///
  /// Later definitions win, matching how incremental updates work.
  void _scanForObjects() {
    const obj = <int>[0x6F, 0x62, 0x6A]; // "obj"
    for (var i = 0; i + 2 < bytes.length; i++) {
      if (bytes[i] != obj[0] ||
          bytes[i + 1] != obj[1] ||
          bytes[i + 2] != obj[2]) {
        continue;
      }
      // Walk back over "  g  n".
      var j = i - 1;
      while (j >= 0 &&
          (bytes[j] == 0x20 || bytes[j] == 0x0D || bytes[j] == 0x0A)) {
        j--;
      }
      final genEnd = j + 1;
      while (j >= 0 && bytes[j] >= 0x30 && bytes[j] <= 0x39) {
        j--;
      }
      final genStart = j + 1;
      if (genStart == genEnd) continue;
      while (j >= 0 &&
          (bytes[j] == 0x20 || bytes[j] == 0x0D || bytes[j] == 0x0A)) {
        j--;
      }
      final numEnd = j + 1;
      while (j >= 0 && bytes[j] >= 0x30 && bytes[j] <= 0x39) {
        j--;
      }
      final numStart = j + 1;
      if (numStart == numEnd) continue;
      if (j >= 0 && !_isDelimiterOrSpace(bytes[j])) continue;
      final number = int.tryParse(
        String.fromCharCodes(bytes.sublist(numStart, numEnd)),
      );
      if (number == null) continue;
      _offsets[number] = numStart;
    }
  }

  static bool _isDelimiterOrSpace(int c) =>
      c == 0x20 ||
      c == 0x0A ||
      c == 0x0D ||
      c == 0x09 ||
      c == 0x3E ||
      c == 0x00;

  void _findRootByScan() {
    for (final number in _offsets.keys.toList()) {
      final o = object(number);
      if (o is PdfDictObj) {
        final type = o['Type'];
        if (type is PdfNameObj && type.value == 'Catalog') {
          _mergeTrailer(
              PdfDictObj(<String, PdfObj>{'Root': PdfRefObj(number, 0)}));
          return;
        }
      }
    }
  }

  // --- object access --------------------------------------------------------

  /// Resolves [o] if it is a reference, otherwise returns it unchanged.
  PdfObj resolve(PdfObj? o) {
    if (o == null) return const PdfNullObj();
    if (o is PdfRefObj) return object(o.number);
    return o;
  }

  PdfObj? _resolveShallow(PdfObj o) => resolve(o);

  /// The object numbered [number], or null-object when unavailable.
  PdfObj object(int number) {
    final cached = _cache[number];
    if (cached != null) return cached;
    if (!_loading.add(number)) return const PdfNullObj(); // cycle guard
    try {
      PdfObj result = const PdfNullObj();
      final offset = _offsets[number];
      if (offset != null && offset >= 0 && offset < bytes.length) {
        result = _parseAt(offset, number);
      }
      if (result is PdfNullObj && _compressed.containsKey(number)) {
        result = _fromObjectStream(number);
      }
      _cache[number] = result;
      return result;
    } finally {
      _loading.remove(number);
    }
  }

  PdfObj _parseAt(int offset, int expected) {
    final lexer = PdfLexer(bytes, offset);
    final num = lexer.next();
    if (num is! PdfNumObj || num.asInt != expected) return const PdfNullObj();
    lexer.next(); // generation
    final kw = lexer.next();
    if (kw is! PdfOperatorObj || kw.name != 'obj') return const PdfNullObj();
    return _readObjectBody(lexer);
  }

  /// Reads the value after `obj`, attaching stream bytes when present.
  PdfObj _readObjectBody(PdfLexer lexer) {
    final value = lexer.next();
    if (value == null) return const PdfNullObj();
    if (value is! PdfDictObj) return value;

    lexer.skipWhitespace();
    final save = lexer.offset;
    final maybeStream = lexer.next();
    if (maybeStream is! PdfOperatorObj || maybeStream.name != 'stream') {
      lexer.offset = save;
      return value;
    }

    // The keyword is followed by CRLF or LF, then the data.
    var start = lexer.offset;
    if (start < bytes.length && bytes[start] == 0x0D) start++;
    if (start < bytes.length && bytes[start] == 0x0A) start++;

    var length = -1;
    final lengthObj = resolve(value['Length']);
    if (lengthObj is PdfNumObj) length = lengthObj.asInt;

    var end =
        (length >= 0 && start + length <= bytes.length) ? start + length : -1;
    // Trust `endstream` over a wrong /Length, which broken writers do emit.
    final marker = _indexOf(bytes, 'endstream', start);
    if (end < 0 || marker < 0 || (marker - start - end + start).abs() > 2) {
      if (marker >= 0) {
        end = marker;
        while (
            end > start && (bytes[end - 1] == 0x0A || bytes[end - 1] == 0x0D)) {
          end--;
        }
      }
    }
    if (end < start) end = start;
    return PdfStreamObj(value, Uint8List.sublistView(bytes, start, end));
  }

  PdfObj _fromObjectStream(int number) {
    final entry = _compressed[number];
    if (entry == null) return const PdfNullObj();
    final (streamNumber, _) = entry;
    final container = object(streamNumber);
    if (container is! PdfStreamObj) return const PdfNullObj();
    final data = decodeStream(container.raw, container.dict, _resolveShallow);
    if (data == null) return const PdfNullObj();

    final n = resolve(container.dict['N']);
    final first = resolve(container.dict['First']);
    if (n is! PdfNumObj || first is! PdfNumObj) return const PdfNullObj();

    final header = PdfLexer(data);
    for (var i = 0; i < n.asInt; i++) {
      final num = header.next();
      final off = header.next();
      if (num is! PdfNumObj || off is! PdfNumObj) break;
      if (num.asInt != number) continue;
      final at = first.asInt + off.asInt;
      if (at < 0 || at >= data.length) break;
      return PdfLexer(data, at).next() ?? const PdfNullObj();
    }
    return const PdfNullObj();
  }

  /// Decoded bytes of [stream], or `null` for image data.
  Uint8List? decoded(PdfStreamObj stream) =>
      decodeStream(stream.raw, stream.dict, _resolveShallow);

  // --- page tree ------------------------------------------------------------

  /// Every page dictionary, in document order, with inherited attributes
  /// (`Resources`, `MediaBox`) folded in.
  List<PdfDictObj> pages() {
    final root = resolve(trailer['Root']);
    final out = <PdfDictObj>[];
    if (root is PdfDictObj) {
      final tree = resolve(root['Pages']);
      if (tree is PdfDictObj) {
        _collectPages(tree, const PdfDictObj(<String, PdfObj>{}), out, <int>{});
      }
    }
    if (out.isEmpty) {
      // Damaged page tree: fall back to every object that looks like a page.
      for (final number in _offsets.keys.toList()..sort()) {
        final o = object(number);
        if (o is PdfDictObj) {
          final type = o['Type'];
          if (type is PdfNameObj && type.value == 'Page') out.add(o);
        }
      }
    }
    return out;
  }

  static const List<String> _inheritable = <String>[
    'Resources',
    'MediaBox',
    'CropBox',
    'Rotate',
  ];

  void _collectPages(
    PdfDictObj node,
    PdfDictObj inherited,
    List<PdfDictObj> out,
    Set<int> seen,
  ) {
    if (out.length > 20000) return;
    final merged = <String, PdfObj>{...inherited.entries};
    for (final key in _inheritable) {
      if (node.has(key)) merged[key] = node[key];
    }

    final type = node['Type'];
    final kids = resolve(node['Kids']);
    if (kids is PdfArrayObj) {
      for (final kid in kids.values) {
        if (kid is PdfRefObj && !seen.add(kid.number)) continue;
        final child = resolve(kid);
        if (child is PdfDictObj) {
          _collectPages(child, PdfDictObj(merged), out, seen);
        }
      }
      return;
    }
    if (type is PdfNameObj && type.value == 'Pages') return;
    out.add(PdfDictObj(<String, PdfObj>{...merged, ...node.entries}));
  }

  /// Concatenated, decoded content streams of [page].
  Uint8List contentOf(PdfDictObj page) {
    final contents = resolve(page['Contents']);
    final parts = <int>[];
    void add(PdfObj o) {
      final s = resolve(o);
      if (s is PdfStreamObj) {
        final data = decoded(s);
        if (data != null) {
          parts
            ..addAll(data)
            ..add(0x0A);
        }
      }
    }

    if (contents is PdfArrayObj) {
      for (final c in contents.values) {
        add(c);
      }
    } else {
      add(contents);
    }
    return Uint8List.fromList(parts);
  }

  static int _indexOf(Uint8List haystack, String needle, int from) {
    final n = needle.codeUnits;
    for (var i = from; i + n.length <= haystack.length; i++) {
      var ok = true;
      for (var k = 0; k < n.length; k++) {
        if (haystack[i + k] != n[k]) {
          ok = false;
          break;
        }
      }
      if (ok) return i;
    }
    return -1;
  }
}
