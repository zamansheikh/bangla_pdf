# VERIFICATION REPORT — bangla_pdf 1.1.0

Every number here was produced by running the code in this repository. Commands
are in §5. Nothing is claimed as passing on the strength of inspection alone.

---

## 1. Summary

| measure | 1.0.6 | 1.1.0 `legacy` | 1.1.0 default (`auto`) |
|---|---|---|---|
| corpus cases that **crash** `pdf.save()` | **21 / 253** | **0 / 253** | **0 / 253** |
| shaping matches HarfBuzz exactly (glyphs + positions) | n/a — not a shaper | n/a | **234 / 234 (100%)** |
| shaping matches HarfBuzz on the glyph sequence | n/a | n/a | **234 / 234 (100%)** |
| text copies back out of the PDF as the original Unicode | **0%** | 0% | **249 / 251 (99%)** |
| Bengali codepoints present in the PDF | **0** | 0 | all of them |
| conjuncts that ligate instead of showing a stray hasanta | table-limited | table-limited | every corpus case |

The two "failures" in the round-trip column are one case: `edge-08` is a lone
ZWJ, which correctly renders as nothing, so the line-by-line comparison shifts
by one. See §3.

---

## 2. Shaping correctness — differential test against HarfBuzz

The Dart shaper is diffed glyph-by-glyph against `hb-shape` (HarfBuzz 14.4.0)
over the 234 corpus cases that are pure Bangla. Mixed-script cases are excluded
because HarfBuzz itemises scripts itself and the comparison would not be
like-for-like.

Fonts: the bundled `Kalpurush-Subset.ttf`, plus Noto Sans Bengali and Noto
Serif Bengali as independent checks.

| category | bundled Kalpurush | Noto Sans | Noto Serif |
|---|---|---|---|
| simple consonants and vowels | 45 / 45 | 45 / 45 | 45 / 45 |
| vowel signs on ক and ম | 21 / 21 | 21 / 21 | 21 / 21 |
| reph | 20 / 20 | 20 / 20 | 20 / 20 |
| reph + conjunct + vowel sign | 8 / 8 | 8 / 8 | 8 / 8 |
| ya-phala / ra-phala | 18 / 18 | 18 / 18 | 18 / 18 |
| 2-consonant conjuncts | 50 / 50 | 50 / 50 | 50 / 50 |
| 3-consonant conjuncts | 14 / 14 | 13 / 14 | 14 / 14 |
| 4-consonant conjuncts | 3 / 3 | 3 / 3 | 3 / 3 |
| hasanta / khanda-ta | 7 / 7 | 7 / 7 | 7 / 7 |
| nukta (NFC and NFD) | 10 / 10 | 10 / 10 | 10 / 10 |
| NFC vs NFD equivalence | 6 / 6 | 6 / 6 | 6 / 6 |
| chandrabindu / anusvara / visarga | 8 / 8 | 7 / 8 | 8 / 8 |
| ZWJ / ZWNJ | 6 / 6 | 6 / 6 | 6 / 6 |
| digits, punctuation, Assamese | 6 / 6 | 6 / 6 | 6 / 6 |
| paragraphs | 4 / 4 | 4 / 4 | 4 / 4 |
| edge cases | 8 / 8 | 8 / 8 | 8 / 8 |
| **total** | **234 / 234 (100%)** | **232 / 234 (99%)** | **234 / 234 (100%)** |

Getting from 98% to 100% took four fixes, each a place where the engine
diverged from the OpenType Indic model:

1. **A ZWNJ after a virama blocks the conjunct.** The half form and the
   ligature must both be suppressed so `haln` can draw an explicit hasanta.
   Without this `ক্‌ষ` silently lost its hasanta.
2. **Ligature input matching is mask-filtered.** A glyph the current feature
   may not touch ends the match rather than being stepped over, which is what
   stops `half` from eating the virama of a following ya-phala. Contextual
   lookups deliberately do *not* filter this way.
3. **Only the Indic features are confined to one syllable.** `rclt`, `calt`,
   `clig` and `rlig` must be allowed to match across syllables, or a font's
   wide-context exception rule never fires and its narrow rule wins wrongly.
4. **GPOS must not zero an attached mark's advance.** Doing so discarded
   `dist` adjustments that had already been applied.

### The two remaining differences

Both are on **Noto Sans Bengali**, which is not the bundled font, and both are
mark *positioning* rather than glyph selection:

| case | difference |
|---|---|
| `conj3-03` ন্ধ্র | one glyph in a mark-to-mark chain sits 279/1000 em too high |
| `mark-04` সংস্কৃতি | the ৃ matra is not attached, so it keeps its default position |

The bundled Kalpurush and Noto Serif Bengali match HarfBuzz on every case.

---

## 3. Round-trip — PDF in, Unicode out

All 251 non-blank corpus cases were rendered to a real PDF through the public
`Text()` widget and extracted with `pdftotext` (poppler 25.x).

**249 / 251 (99%)** come back identical to the source after NFC normalisation
and whitespace collapsing.

The two exceptions are a single artefact: `edge-08` is a lone ZWJ. It shapes to
no glyphs (correct — a joiner is invisible), so it contributes no line to the
extracted text and the subsequent line-by-line comparison is off by one.
`edge-09` is therefore reported as failing although its text is correct.

Extraction is exact because each line is wrapped in a
`/Span <</ActualText …>> BDC … EMC` marked-content span carrying the logical
UTF-16 string. That is what makes copy/paste survive glyph reordering: Bengali
draws ি *before* the consonant it follows, so no per-glyph mapping can express
logical order on its own.

Verified independently at the PDF-structure level by
`test/pdf_output_test.dart`:

* the font is `/Type0` + `/Identity-H` + `/CIDFontType2` with a `/CIDToGIDMap`;
* every `/ToUnicode` `bfchar` destination is real Unicode — no U+FFFD, no NUL;
* the CMap contains Bengali codepoints (1.0.6's contained only Latin-1);
* one `/ActualText` span is opened and closed per rendered line;
* the `/ActualText` payloads decode back to the source strings exactly.

---

## 4. Regression — `legacy` mode is strictly better than 1.0.6

The 1.0.x Bijoy pipeline is retained verbatim apart from bounds checks in
`_rearrangeUnicodeStr`.

| | 1.0.6 | 1.1.0 legacy |
|---|---|---|
| corpus cases throwing `RangeError` | 21 | **0** |
| output changed on a case that already worked | — | **0** |

The 21 crashes were all reph: `কর্ম` `ধর্ম` `বর্ষ` `পূর্ব` `শর্ত` `র্ক` and
friends threw an uncaught `RangeError` out of `pw.Widget.build`, aborting
`pdf.save()` entirely. Verified byte-for-byte that no previously-working case
produces different ANSI output.

---

## 5. Reproducing

```bash
flutter test                                   # 18 tests: shaping, PDF structure, widgets

# differential test against HarfBuzz (needs `brew install harfbuzz`)
dart run tool/dev/shape_dump.dart test/fixtures/fonts/Kalpurush-Subset.ttf < strings.txt
hb-shape --no-glyph-names --font-funcs=ot test/fixtures/fonts/Kalpurush-Subset.ttf 'কর্ম'

# round-trip (needs `brew install poppler`)
dart run tool/dev/corpus_pdf.dart test/fixtures/fonts/Kalpurush-Subset.ttf \
    test/corpus/bangla_cases.json /tmp/corpus.pdf
pdftotext -nopgbrk /tmp/corpus.pdf -

# 1.0.6 baseline, for the "before" column
dart run tool/baseline/run_106_mapper.dart docs/baseline/phase1_probe_cases.json
```

---

## 6. What has **not** been verified

Stated plainly, because the project rule is not to claim a pass without
evidence:

* **No pixel-diff golden images.** Rendering was checked by rasterising with
  `pdftoppm` and comparing against `hb-view` reference renders by eye for a
  sample of cases, not by an automated per-case pixel diff of all 253. The
  per-case diff harness is not built.
* **No cross-viewer matrix.** Copy/paste was verified with poppler
  (`pdftotext`) only. Adobe Reader, macOS Preview, Chrome's viewer and Android
  viewers have not been tested, and `/ActualText` support does vary.
* **Extraction (`package:bangla_pdf/extract.dart`) does not exist yet.** No
  Bijoy→Unicode reverse mapping, no scanned-PDF detection, no `ocrHook`.
* **No real-world PDF fixtures.** The 10 sample PDFs were never supplied, so
  nothing has been measured against government notices, invoices, newspaper
  pages or scans.
* **Three fonts tested.** Bundled Kalpurush (234/234), Noto Serif Bengali
  (234/234), Noto Sans Bengali (232/234). SolaimanLipi is untested.
* **No HarfBuzz companion package.** `bangla_pdf_harfbuzz` and
  `BanglaShapingMode.harfbuzz` are not implemented; the mode enum currently
  offers `auto`, `unicode` and `legacy`.
* **Font embedding is not subsetted per document.** The whole bundled font
  (121 KB) is embedded in every PDF.
