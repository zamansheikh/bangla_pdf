/// The PDF object model used when *reading* a document.
///
/// `package:pdf` models objects for writing only, so extraction needs its own
/// representation. Kept deliberately small: enough to walk a page tree, resolve
/// fonts and decode content streams.
library;

import 'dart:typed_data';

/// Base class for every value that can appear in a PDF file.
sealed class PdfObj {
  const PdfObj();
}

/// `null`, and the value returned for anything unresolvable.
class PdfNullObj extends PdfObj {
  const PdfNullObj();
  @override
  String toString() => 'null';
}

/// `true` / `false`.
class PdfBoolObj extends PdfObj {
  const PdfBoolObj(this.value);
  final bool value;
  @override
  String toString() => '$value';
}

/// An integer or real.
class PdfNumObj extends PdfObj {
  const PdfNumObj(this.value);
  final double value;

  /// The value as an `int`, truncating.
  int get asInt => value.toInt();

  @override
  String toString() => '$value';
}

/// A name, stored without the leading slash.
class PdfNameObj extends PdfObj {
  const PdfNameObj(this.value);
  final String value;
  @override
  String toString() => '/$value';
}

/// A literal `(…)` or hex `<…>` string, kept as raw bytes.
///
/// PDF strings are byte strings; how they decode depends on the font, so the
/// bytes are preserved and interpreted later.
class PdfStringObj extends PdfObj {
  const PdfStringObj(this.bytes);
  final Uint8List bytes;

  /// The bytes as Latin-1, which is how single-byte PDF encodings work.
  String get asLatin1 => String.fromCharCodes(bytes);

  @override
  String toString() => '($asLatin1)';
}

/// An array.
class PdfArrayObj extends PdfObj {
  const PdfArrayObj(this.values);
  final List<PdfObj> values;

  /// Element [i], or null-object when out of range.
  PdfObj operator [](int i) =>
      (i >= 0 && i < values.length) ? values[i] : const PdfNullObj();

  int get length => values.length;

  @override
  String toString() => '[${values.join(' ')}]';
}

/// A dictionary. Keys are stored without the leading slash.
class PdfDictObj extends PdfObj {
  const PdfDictObj(this.entries);
  final Map<String, PdfObj> entries;

  /// Raw (unresolved) value for [key].
  PdfObj operator [](String key) => entries[key] ?? const PdfNullObj();

  bool has(String key) => entries.containsKey(key);

  @override
  String toString() =>
      '<<${entries.entries.map((e) => '/${e.key} ${e.value}').join(' ')}>>';
}

/// A stream: a dictionary plus its raw, still-encoded bytes.
class PdfStreamObj extends PdfObj {
  const PdfStreamObj(this.dict, this.raw);
  final PdfDictObj dict;
  final Uint8List raw;

  @override
  String toString() => '<<stream ${raw.length} bytes>>';
}

/// An indirect reference, `n g R`.
class PdfRefObj extends PdfObj {
  const PdfRefObj(this.number, this.generation);
  final int number;
  final int generation;

  @override
  bool operator ==(Object other) =>
      other is PdfRefObj &&
      other.number == number &&
      other.generation == generation;

  @override
  int get hashCode => Object.hash(number, generation);

  @override
  String toString() => '$number $generation R';
}

/// A bare keyword such as `obj`, `endobj`, `stream` or a content operator.
class PdfOperatorObj extends PdfObj {
  const PdfOperatorObj(this.name);
  final String name;
  @override
  String toString() => name;
}
