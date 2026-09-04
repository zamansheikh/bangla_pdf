/// Indic syllabic categories and positions for the Bengali block.
///
/// Mirrors the categorisation the OpenType Indic (`bng2`) shaping model
/// expects. Values are Bengali-specific: this is not a general Indic table.
library;

/// Indic syllabic category.
enum IndicCategory {
  /// Anything with no syllabic role (Latin, punctuation, spaces).
  other,

  /// Consonant.
  consonant,

  /// The letter RA, which can become a reph or a ra-phala.
  ra,

  /// Independent vowel.
  vowel,

  /// Nukta, U+09BC.
  nukta,

  /// Halant / virama, U+09CD.
  halant,

  /// Zero-width non-joiner, U+200C.
  zwnj,

  /// Zero-width joiner, U+200D.
  zwj,

  /// Dependent vowel sign (matra).
  matra,

  /// Syllable modifier: candrabindu, anusvara, visarga.
  syllableModifier,

  /// Avagraha and other placeholders that can carry a syllable.
  placeholder,

  /// Bengali digit.
  digit,

  /// Currency and other Bengali symbols.
  symbol,
}

/// Position within a syllable. Ordering is significant: the initial reordering
/// pass stable-sorts each syllable by this value.
class IndicPosition {
  static const int start = 0;
  static const int raToBecomeReph = 1;
  static const int preMatra = 2;
  static const int preConsonant = 3;
  static const int baseConsonant = 4;
  static const int afterMain = 5;
  static const int aboveConsonant = 6;
  static const int beforeSub = 7;
  static const int belowConsonant = 8;
  static const int afterSub = 9;
  static const int beforePost = 10;
  static const int postConsonant = 11;
  static const int afterPost = 12;
  static const int smvd = 13;
  static const int end = 14;
}

/// U+09CD BENGALI SIGN VIRAMA.
const int kVirama = 0x09CD;

/// U+09B0 BENGALI LETTER RA.
const int kRa = 0x09B0;

/// U+09F0 BENGALI LETTER RA WITH MIDDLE DIAGONAL (Assamese).
const int kAssameseRa = 0x09F0;

/// U+09BC BENGALI SIGN NUKTA.
const int kNukta = 0x09BC;

/// U+200C ZERO WIDTH NON-JOINER.
const int kZwnj = 0x200C;

/// U+200D ZERO WIDTH JOINER.
const int kZwj = 0x200D;

/// U+25CC DOTTED CIRCLE.
const int kDottedCircle = 0x25CC;

/// Two-part Bengali vowel signs, decomposed the way the shaping model expects.
///
/// Fonts' GSUB rules are written against the decomposed forms, so we always
/// decompose before shaping and recompose only for the `/ToUnicode` text.
const Map<int, List<int>> kMatraDecomposition = <int, List<int>>{
  0x09CB: <int>[0x09C7, 0x09BE], // ো  = e + aa
  0x09CC: <int>[0x09C7, 0x09D7], // ৌ  = e + au length mark
};

/// Canonical compositions for consonant + nukta, applied before shaping so
/// that both NFC and NFD input shape identically.
const Map<int, int> kNuktaComposition = <int, int>{
  0x09A1: 0x09DC, // ড + ় = ড়
  0x09A2: 0x09DD, // ঢ + ় = ঢ়
  0x09AF: 0x09DF, // য + ় = য়
};

/// Reverse of [kNuktaComposition], used when reporting source text.
const Map<int, List<int>> kNuktaDecomposition = <int, List<int>>{
  0x09DC: <int>[0x09A1, 0x09BC],
  0x09DD: <int>[0x09A2, 0x09BC],
  0x09DF: <int>[0x09AF, 0x09BC],
};

/// Syllabic category of [cp].
IndicCategory categoryOf(int cp) {
  switch (cp) {
    case kNukta:
      return IndicCategory.nukta;
    case kVirama:
      return IndicCategory.halant;
    case kZwnj:
      return IndicCategory.zwnj;
    case kZwj:
      return IndicCategory.zwj;
    case kRa:
    case kAssameseRa:
      return IndicCategory.ra;
    case 0x0981: // candrabindu
    case 0x0982: // anusvara
    case 0x0983: // visarga
      return IndicCategory.syllableModifier;
    case 0x09BD: // avagraha
    case kDottedCircle:
      return IndicCategory.placeholder;
    case 0x09CE: // khanda ta - a consonant that never takes a virama
      return IndicCategory.consonant;
    case 0x0980: // anji
      return IndicCategory.placeholder;
  }

  // Independent vowels.
  if ((cp >= 0x0985 && cp <= 0x098C) ||
      cp == 0x098F ||
      cp == 0x0990 ||
      cp == 0x0993 ||
      cp == 0x0994 ||
      cp == 0x09E0 ||
      cp == 0x09E1) {
    return IndicCategory.vowel;
  }

  // Consonants, including the nukta-composed forms and Assamese wa.
  if ((cp >= 0x0995 && cp <= 0x09A8) ||
      (cp >= 0x09AA && cp <= 0x09B0) ||
      cp == 0x09B2 ||
      (cp >= 0x09B6 && cp <= 0x09B9) ||
      cp == 0x09DC ||
      cp == 0x09DD ||
      cp == 0x09DF ||
      cp == 0x09F1) {
    return IndicCategory.consonant;
  }

  // Dependent vowel signs.
  if ((cp >= 0x09BE && cp <= 0x09C4) ||
      cp == 0x09C7 ||
      cp == 0x09C8 ||
      cp == 0x09CB ||
      cp == 0x09CC ||
      cp == 0x09D7 ||
      cp == 0x09E2 ||
      cp == 0x09E3) {
    return IndicCategory.matra;
  }

  if (cp >= 0x09E6 && cp <= 0x09EF) return IndicCategory.digit;
  if (cp >= 0x09F2 && cp <= 0x09FE) return IndicCategory.symbol;

  return IndicCategory.other;
}

/// Default position of a matra or modifier, before base-relative adjustment.
int defaultPositionOf(int cp) {
  switch (cp) {
    // Pre-base vowel signs: these render to the LEFT of the cluster.
    case 0x09BF: // ি
    case 0x09C7: // ে
    case 0x09C8: // ৈ
      return IndicPosition.preMatra;

    // Below-base vowel signs.
    case 0x09C1: // ু
    case 0x09C2: // ূ
    case 0x09C3: // ৃ
    case 0x09C4: // ৄ
    case 0x09E2: // ৢ
    case 0x09E3: // ৣ
      return IndicPosition.belowConsonant;

    // Post-base vowel signs.
    case 0x09BE: // া
    case 0x09C0: // ী
    case 0x09D7: // ৗ
      return IndicPosition.postConsonant;

    // Syllable modifiers sit after everything.
    case 0x0981: // ঁ
    case 0x0982: // ং
    case 0x0983: // ঃ
      return IndicPosition.smvd;

    case kNukta:
      return IndicPosition.afterMain;
  }
  return IndicPosition.baseConsonant;
}

/// Whether [cp] is a consonant for the purposes of base finding.
bool isConsonantCategory(IndicCategory c) =>
    c == IndicCategory.consonant ||
    c == IndicCategory.ra ||
    c == IndicCategory.placeholder;
