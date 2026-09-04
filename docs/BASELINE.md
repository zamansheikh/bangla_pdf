# BASELINE — `bangla_pdf` 1.0.6, measured

The "before" column for the README. Produced by running the **unmodified** 1.0.6 code.
Regenerate with the commands in §5.

> **Scope note.** This is the Phase 1 baseline over an **84-case probe corpus**, not the
> full ≥150-case Phase 2 corpus, and it is a **text-level + spot-rasterised** baseline,
> not the full per-case pixel-diff run. The full corpus and the full golden-image run are
> Phase 2 and Phase 4 respectively, and both are blocked on the fixtures listed in §6.
> Nothing here claims a case *renders* correctly.

---

## 1. Method

1. `lib/src/utils/unicode_mapper.dart` was copied verbatim (only the `part of` line
   removed) into a standalone Dart program, so the shipped transform runs unaltered.
2. Each of the 84 corpus strings was passed through `BanglaUnicodeMapper.encodeANSI`,
   capturing output or exception. → [`phase1_probe_results.json`](baseline/phase1_probe_results.json)
3. The embedded font was base64-decoded out of `default_font_data.dart` and its `cmap`
   parsed, to tell "produced a mapped glyph" from "produced a notdef".
4. Selected outputs were **rasterised with `hb-view`** against the real embedded font,
   and the same source strings rasterised against Noto Sans Bengali, for a visual
   reference pair.
5. A real PDF was generated through the full widget stack (`Text` → `AutoText` →
   `FixingUtils` → `pw.RichText` → `PdfTtfFont`) and its content stream and
   `/ToUnicode` CMap parsed, to measure copy/paste.
6. The reph crash was isolated with a probe that reproduces
   `FixingUtils.getAutoLocalizedSpans`' exact run-splitting regex.

Verdicts:

* **ok** — transcode produced a fully-mapped glyph sequence with no unintended visible
  hasanta. **Text-level only.**
* **BROKEN** — conjunct not ligated; renders as base + visible hasanta (`্`) + base.
* **NOGLYPH** — a codepoint reached the font that its `cmap` does not cover → notdef.
* **CRASH** — uncaught `RangeError` propagates out of `pw.Widget.build`, aborting
  `pdf.save()`.

---

## 2. Summary

| category | cases | ok\* | BROKEN | NOGLYPH | CRASH |
|---|---|---|---|---|---|
| conjunct | 14 | 9 | 5 | 0 | 0 |
| digits | 4 | 2 | 0 | 2 | 0 |
| edge | 7 | 4 | 0 | 0 | 3 |
| hasanta | 4 | 4 | 0 | 0 | 0 |
| marks | 3 | 3 | 0 | 0 | 0 |
| mixed | 2 | 1 | 0 | 1 | 0 |
| normalisation | 4 | 4 | 0 | 0 | 0 |
| nukta | 3 | 3 | 0 | 0 | 0 |
| paragraph | 6 | 6 | 0 | 0 | 0 |
| phala | 7 | 7 | 0 | 0 | 0 |
| reph | 11 | 1 | 0 | 0 | 10 |
| simple | 4 | 4 | 0 | 0 | 0 |
| vowelsign | 11 | 11 | 0 | 0 | 0 |
| zwj | 4 | 3 | 0 | 0 | 1 |
| **TOTAL** | **84** | **62** | **5** | **3** | **14** |

**Every one of the 84 cases fails the copy/paste round-trip**, independently of the
verdict above, because the PDF contains Bijoy-ANSI Latin-1 rather than Bengali (§4).

### The two dominant failure clusters

* **reph — 10 of 11 cases crash.** Not "renders wrongly": throws. `কর্ম`, `ধর্ম`,
  `বর্ষ`, `পূর্ব`, `শর্ত` all abort PDF generation when the word ends a Bangla run.
  This is the single highest-severity finding of Phase 1.
* **conjuncts — 5 of 14 broken.** `ক্ষ্ম`, `ঙ্ক্ষ`, `ত্ত্ব`, `চ্ছ্ব`, `ম্ভ্র` all render
  with a visible hasanta instead of ligating. Four of those five have a *correct entry in
  `_conversionMap` that can never fire* because an earlier, shorter key consumes the
  input first (see AUDIT §1 row 14).

---

## 3. Rasterised evidence

`hb-view` at 48 px, left = what 1.0.6 puts in the PDF (its ANSI output through the
embedded Kalpurush ANSI), right = the same source strings through Noto Sans Bengali with
HarfBuzz.

Source: `ক্ষ্ম ঙ্ক্ষ ত্ত্ব চ্ছ্ব ম্ভ্র স্ত্র্য`

| | rendered |
|---|---|
| 1.0.6 output | `ক্ষ্‌ম ঙ্‌ক্ষ ত্ত্‌ব চ্ছ্‌ব ম্‌ভ্র স্তর্য` — every one shows a stray hasanta or a decomposed cluster |
| HarfBuzz reference | `ক্ষ্ম ঙ্ক্ষ ত্ত্ব চ্ছ্ব ম্ভ্র স্ত্র্য` — all correctly ligated |

Source: `আমার সোনার বাংলা, আমি তোমায় ভালোবাসি।` — **both render correctly.** 1.0.6 is
genuinely fine on ordinary prose that avoids reph-final words and rare conjuncts, which
is why it has happy users. The failures are concentrated, not diffuse.

`hb-shape` ground truth used as the Phase 4 oracle, e.g.

```
$ hb-shape NotoSansBengali-Regular.ttf 'কর্ম'
[kabeng=0+807|mabeng=1+622|rephbeng=1+0]
$ hb-shape NotoSansBengali-Regular.ttf 'ক্ষ্ম'
[kassamabeng=0+1066]
$ hb-shape NotoSansBengali-Regular.ttf 'কি'
[ivowelsignbeng=0+266|kabeng=0+807]
```

---

## 4. Copy/paste — measured, not inferred

A PDF was generated with unmodified 1.0.6 containing
`আমার সোনার বাংলা, আমি তোমায় ভালোবাসি।`, `ক্ষ্ম ঙ্ক্ষ ত্ত্ব চ্ছ্ব ম্ভ্র` and
`Hello বাংলাদেশ world!`.

* PDF size: 9,438 bytes
* `/ToUnicode` CMap: 26 `bfchar` entries, all mapping to Latin-1
* Bengali codepoints anywhere in the file: **0**

Text recovered by walking the content stream through the file's own `/ToUnicode` — i.e.
exactly what a viewer places on the clipboard:

```
Avgvi ‡mvbvi evsjv , Avwg ‡Zvgvq fv‡jvevwm| ¶&g O&¶ Ë&e ”Q&e g&å Hello evsjv‡`k world!
```

`pdftotext`, in-viewer search, screen readers and any downstream text extraction get
this string. **Round-trip accuracy of 1.0.6 is 0%.**

---

## 5. Reproducing

```bash
dart run tool/baseline/run_106_mapper.dart docs/baseline/phase1_probe_cases.json
dart run tool/baseline/reph_crash_probe.dart
python3 tool/baseline/ttfinfo.py <font.ttf>
```

The PDF-level measurement in §4 needs a throwaway `flutter test` that calls the widgets
and writes `pdf.save()` to disk; it is not committed because `test/` is reserved for the
Phase 2 corpus harness.

---

## 6. What is still missing before this can be called complete

Blocked on you (see the Phase 1 summary):

* **Real font fixtures** — Kalpurush (**Unicode**, not the ANSI one bundled today),
  Noto Sans Bengali, Noto Serif Bengali, SolaimanLipi. Only Noto Sans Bengali is
  currently available, borrowed from another package's cache.
* **The 10 real-world PDFs** — 3 Bijoy government notices, 3 Unicode invoices,
  2 newspaper pages, 2 scans. Nothing in Phase 5 can be measured without them.
* **A PDF rasteriser.** `pdftoppm` is not installed on this machine. Chrome and the
  HarfBuzz CLI tools are. Phase 4 needs either `brew install poppler` or an agreed
  alternative.

## 7. Full per-case table

| id | category | input | 1.0.6 ANSI output | verdict | detail |
|---|---|---|---|---|---|
| `vowel-00` | vowelsign | ক | <code>K</code> | **ok** |  |
| `vowel-01` | vowelsign | কা | <code>Kv</code> | **ok** |  |
| `vowel-02` | vowelsign | কি | <code>wK</code> | **ok** |  |
| `vowel-03` | vowelsign | কী | <code>Kx</code> | **ok** |  |
| `vowel-04` | vowelsign | কু | <code>Ky</code> | **ok** |  |
| `vowel-05` | vowelsign | কূ | <code>K~</code> | **ok** |  |
| `vowel-06` | vowelsign | কৃ | <code>K…</code> | **ok** |  |
| `vowel-07` | vowelsign | কে | <code>‡K</code> | **ok** |  |
| `vowel-08` | vowelsign | কৈ | <code>‰K</code> | **ok** |  |
| `vowel-09` | vowelsign | কো | <code>‡Kv</code> | **ok** |  |
| `vowel-10` | vowelsign | কৌ | <code>‡KŠ</code> | **ok** |  |
| `indep-00` | simple | অআইঈউঊঋএঐওঔ | <code>AAvBCDEFGHIJ</code> | **ok** |  |
| `simple-00` | simple | কখগঘঙচছজঝঞ | <code>KLMNOPQRST</code> | **ok** |  |
| `simple-01` | simple | টঠডঢণতথদধন | <code>UVWXYZ_`ab</code> | **ok** |  |
| `simple-02` | simple | পফবভমযরলশষসহ | <code>cdefghijklmn</code> | **ok** |  |
| `reph-00` | reph | র্ক | — | **CRASH** | uncaught `RangeError` escapes into `pw.Widget.build` |
| `reph-01` | reph | র্ম | — | **CRASH** | uncaught `RangeError` escapes into `pw.Widget.build` |
| `reph-02` | reph | র্য | — | **CRASH** | uncaught `RangeError` escapes into `pw.Widget.build` |
| `reph-03` | reph | র্যা | — | **CRASH** | uncaught `RangeError` escapes into `pw.Widget.build` |
| `reph-04` | reph | কর্ম | — | **CRASH** | uncaught `RangeError` escapes into `pw.Widget.build` |
| `reph-05` | reph | বর্ষ | — | **CRASH** | uncaught `RangeError` escapes into `pw.Widget.build` |
| `reph-06` | reph | দুর্গা | <code>`yM©v</code> | **ok** |  |
| `reph-07` | reph | র্তি | — | **CRASH** | uncaught `RangeError` escapes into `pw.Widget.build` |
| `reph-08` | reph | র্ত্তি | — | **CRASH** | uncaught `RangeError` escapes into `pw.Widget.build` |
| `reph-09` | reph | র্ষ্ণে | — | **CRASH** | uncaught `RangeError` escapes into `pw.Widget.build` |
| `reph-10` | reph | র্ক্ষ্য | — | **CRASH** | uncaught `RangeError` escapes into `pw.Widget.build` |
| `phala-00` | phala | ব্য | <code>e¨</code> | **ok** |  |
| `phala-01` | phala | ক্র | <code>µ</code> | **ok** |  |
| `phala-02` | phala | প্র | <code>cª</code> | **ok** |  |
| `phala-03` | phala | স্ত্র | <code>¯¿</code> | **ok** |  |
| `phala-04` | phala | গ্র্য | <code>Mª¨</code> | **ok** |  |
| `phala-05` | phala | ম্র | <code>gª</code> | **ok** |  |
| `phala-06` | phala | হ্য | <code>n¨</code> | **ok** |  |
| `conj-00` | conjunct | ক্ষ | <code>¶</code> | **ok** |  |
| `conj-01` | conjunct | জ্ঞ | <code>Á</code> | **ok** |  |
| `conj-02` | conjunct | ষ্ণ | <code>ò</code> | **ok** |  |
| `conj-03` | conjunct | ন্ত্র | <code>š¿</code> | **ok** |  |
| `conj-04` | conjunct | ক্ষ্ম | <code>¶&amp;g</code> | **BROKEN** | conjunct not ligated — renders base + visible hasanta (্) |
| `conj-05` | conjunct | ঙ্ক্ষ | <code>O&amp;¶</code> | **BROKEN** | conjunct not ligated — renders base + visible hasanta (্) |
| `conj-06` | conjunct | স্ত্র্য | <code>¯Zª¨</code> | **ok** |  |
| `conj-07` | conjunct | ন্ধ্র | <code>Üª</code> | **ok** |  |
| `conj-08` | conjunct | ক্ত | <code>³</code> | **ok** |  |
| `conj-09` | conjunct | দ্ধ | <code>×</code> | **ok** |  |
| `conj-10` | conjunct | ল্ল | <code>jø</code> | **ok** |  |
| `conj-11` | conjunct | ত্ত্ব | <code>Ë&amp;e</code> | **BROKEN** | conjunct not ligated — renders base + visible hasanta (্) |
| `conj-12` | conjunct | চ্ছ্ব | <code>”Q&amp;e</code> | **BROKEN** | conjunct not ligated — renders base + visible hasanta (্) |
| `conj-13` | conjunct | ম্ভ্র | <code>g&amp;å</code> | **BROKEN** | conjunct not ligated — renders base + visible hasanta (্) |
| `has-00` | hasanta | বাক্‌ | <code>evK&amp;</code> | **ok** |  |
| `has-01` | hasanta | ৎ | <code>r</code> | **ok** |  |
| `has-02` | hasanta | ত্ | <code>Z&amp;</code> | **ok** |  |
| `has-03` | hasanta | উৎসব | <code>Drme</code> | **ok** |  |
| `nuk-00` | nukta | ড়ঢ়য় | <code>opq</code> | **ok** |  |
| `nuk-01` | nukta | ড়ঢ়য় | <code>opq</code> | **ok** |  |
| `nuk-02` | nukta | বাংলাদেশ | <code>evsjv‡`k</code> | **ok** |  |
| `mark-00` | marks | চাঁদ | <code>Pvu`</code> | **ok** |  |
| `mark-01` | marks | বাংলা | <code>evsjv</code> | **ok** |  |
| `mark-02` | marks | দুঃখ | <code>`ytL</code> | **ok** |  |
| `num-00` | digits | ০১২৩৪৫৬৭৮৯ | <code>0123456789</code> | **ok** |  |
| `num-01` | digits | ৳ ১২৩৪.৫৬ | <code>$ 1234.56</code> | **ok** |  |
| `num-02` | digits | ৰ ৱ | <code>ৰ ৱ</code> | **NOGLYPH** | font has no glyph for U+09F0 U+09F1 |
| `num-03` | digits | বাক্য। শেষ॥ | <code>evK¨&#124; ‡kl॥</code> | **NOGLYPH** | font has no glyph for U+0965 |
| `mix-00` | mixed | আমার Invoice #123 total ৳৫০০ ✅ | <code>Avgvi Invoice #123 total $500 ✅</code> | **NOGLYPH** | font has no glyph for U+2705 |
| `mix-01` | mixed | Hello বাংলাদেশ world! | <code>Hello evsjv‡`k world!</code> | **ok** |  |
| `zwj-00` | zwj | র‍্য | <code>i¨</code> | **ok** |  |
| `zwj-01` | zwj | র্য | — | **CRASH** | uncaught `RangeError` escapes into `pw.Widget.build` |
| `zwj-02` | zwj | ক্‌ষ | <code>K&amp;l</code> | **ok** |  |
| `zwj-03` | zwj | ক্ষ | <code>¶</code> | **ok** |  |
| `norm-00` | normalisation | ড়া | <code>ov</code> | **ok** |  |
| `norm-01` | normalisation | ড়া | <code>ov</code> | **ok** |  |
| `norm-02` | normalisation | কো | <code>‡Kv</code> | **ok** |  |
| `norm-03` | normalisation | কো | <code>‡Kv</code> | **ok** |  |
| `para-00` | paragraph | আমার সোনার বাংলা, আমি তোমায় ভালোবাসি। | <code>Avgvi ‡mvbvi evsjv, Avwg ‡Zvgvq fv‡jvevwm&#124;</code> | **ok** |  |
| `para-01` | paragraph | চিরদিন তোমার আকাশ, তোমার বাতাস, আমার প্রাণে বাজায় বাঁশি। | <code>wPiw`b ‡Zvgvi AvKvk, ‡Zvgvi evZvm, Avgvi cªv‡Y evRvq evuwk&#124;</code> | **ok** |  |
| `para-02` | paragraph | ঢাকা বিশ্ববিদ্যালয়ের শিক্ষার্থীরা গতকাল কেন্দ্রীয় শহীদ মিনারে সমাবেশ করেছেন। | <code>XvKv wek¦we`¨vj‡qi wk¶v_©xiv MZKvj ‡K›`ªxq knx` wgbv‡i mgv‡ek K‡i‡Qb&#124;</code> | **ok** |  |
| `para-03` | paragraph | বিবরণ: কম্পিউটার যন্ত্রাংশ — পরিমাণ ৩ — একক মূল্য ৳১২,৫০০.০০ — তারিখ ০১/০৯/২০২৬ | <code>weeiY: Kw¤úDUvi hš¿vsk — cwigvY 3 — GKK g~j¨ $12,500.00 — ZvwiL 01/09/2026</code> | **ok** |  |
| `para-04` | paragraph | উক্ত চুক্তির শর্তাবলী লঙ্ঘিত হইলে কর্তৃপক্ষ আইনানুগ ব্যবস্থা গ্রহণ করিবেন। | <code>D³ Pyw³i kZ©vejx jw•NZ nB‡j KZ©…c¶ AvBbvbyM e¨e¯’v MªnY Kwi‡eb&#124;</code> | **ok** |  |
| `para-05` | paragraph | স্থিতি: ৳৪৫,৬৭৮.৯০ &#124; লেনদেন: ডেবিট &#124; শাখা: মতিঝিল | <code>w¯’wZ: $45,678.90 &#124; ‡jb‡`b: ‡WweU &#124; kvLv: gwZwSj</code> | **ok** |  |
| `edge-00` | edge | ি | — | **CRASH** | uncaught `RangeError` escapes into `pw.Widget.build` |
| `edge-01` | edge | ে | — | **CRASH** | uncaught `RangeError` escapes into `pw.Widget.build` |
| `edge-02` | edge |  ি | <code>w </code> | **ok** |  |
| `edge-03` | edge | র্ | <code>©</code> | **ok** |  |
| `edge-04` | edge | ্র | — | **CRASH** | uncaught `RangeError` escapes into `pw.Widget.build` |
| `edge-05` | edge | aি | <code>wa</code> | **ok** |  |
| `edge-06` | edge | _(empty)_ | <code></code> | **ok** |  |
