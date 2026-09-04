# ADR 001 — Shaping engine for `bangla_pdf` 2.x

* **Status:** proposed — awaiting owner sign-off on the two decisions in §7
* **Date:** 2026-09-05
* **Context docs:** [CURRENT_STATE.md](../CURRENT_STATE.md), [AUDIT.md](../AUDIT.md), [BASELINE.md](../BASELINE.md)

---

## 1. Context

1.0.6 transcodes Unicode to Bijoy-ANSI and renders with a 231-glyph 8-bit font. It has no
shaping model beyond two reorder rules; it crashes on reph-final words; and its PDFs
contain no Bengali text at all, so copy/paste, search and extraction return mojibake
(BASELINE §4).

`bangla_pdf_fixer` 3.1.1 already solved *shaping* correctly with HarfBuzz over FFI. It
did not solve web support, PDF text fidelity, or file size — it paints glyph outlines and
bolts on an invisible text overlay (AUDIT §0, §2).

The goal for `bangla_pdf` is therefore not "add shaping". It is **shaping + real
glyph-addressed PDF text + web + no crash + zero-config**, without breaking 1.x users.

---

## 2. Options

### (a) Pure-Dart OpenType GSUB/GPOS shaping

Implement the Indic (`bng2`) shaper in Dart: cluster segmentation, syllable
categorisation, reordering (reph, pre-base matras, post-base forms), then GSUB lookup
types 1/2/4/5/6 with the Bengali feature order (`nukt akhn rphf blwf half pstf vatu
cjct` → `pres abvs blws psts haln` → `calt clig`), then GPOS types 1/2/4/5/6 plus `GDEF`
mark classes.

Measured scope against Noto Sans Bengali 2.002: `GSUB` 10,520 bytes, 61 lookups, 14
features, script `bng2`; `GPOS` 6,796 bytes.

| | |
|---|---|
| **+** | works on **every** platform including web, with no native toolchain |
| **+** | no new runtime dependency; package stays pure Dart |
| **+** | full control over glyph ids → we can emit a proper Type0 font |
| **−** | this is the hard part of a text engine. HarfBuzz's Indic shaper is ~4k lines of C++ with a decade of bug fixes behind it |
| **−** | correctness risk is concentrated exactly where Bangla is hard (3–4 consonant conjuncts, reph + pre-base matra interactions) |
| **−** | realistically 3–6 weeks to reach parity on a 150-case corpus, and a permanent maintenance surface |

### (b) HarfBuzz via FFI everywhere

Bind HarfBuzz (`harfbuzz_ffi`, or our own bindings) on native; `harfbuzzjs` WASM on web.

| | |
|---|---|
| **+** | correctness is HarfBuzz's, i.e. correct |
| **+** | fastest route to a passing corpus |
| **−** | `harfbuzz_ffi` 0.5.0 uses Dart **native build hooks** (`hooks`, `code_assets`, `native_toolchain_c`) and compiles `harfbuzz-world.cc` from a 7.6 MB bundled source tree at build time. That forces Dart ≥ 3.13, a working C toolchain on every contributor's and every CI machine, and native-assets support in whatever Flutter channel the user is on |
| **−** | it raises `bangla_pdf`'s SDK floor from `^3.5.4` to `^3.13.0` — **a breaking change for existing users on older SDKs** |
| **−** | web needs a completely separate WASM path (`harfbuzzjs`), asynchronous init, and a second correctness surface |
| **−** | binary size on every native platform (§5) for users who may only ever set one Bangla label |

### (c) Hybrid — HarfBuzz when available, improved Dart reorder engine otherwise ✅ **recommended**

`bangla_pdf` stays pure Dart and ships an improved reorder/shaping engine. An optional
companion package `bangla_pdf_harfbuzz` provides the HarfBuzz backend and registers
itself at runtime; `bangla_pdf` detects it through a registration hook (no import, no
conditional-import gymnastics, no dependency).

```dart
enum BanglaShapingMode {
  /// HarfBuzz if bangla_pdf_harfbuzz is registered, else the built-in engine.
  auto,
  /// Require HarfBuzz; throw a clear error if the companion is absent.
  harfbuzz,
  /// Force the built-in engine. Also the 1.x-compatible ANSI path (see §7.1).
  legacy,
}
```

| | |
|---|---|
| **+** | SDK floor unchanged; no toolchain requirement for the default install |
| **+** | web works out of the box on the built-in engine |
| **+** | HarfBuzz correctness available to anyone who wants it, opt-in and paid-for only by them |
| **+** | the built-in engine is exercised by every user, so it stays honest — no dead fallback path |
| **−** | two shaping implementations to keep in agreement; the corpus must run in both modes (Phase 4 item 5 already requires this) |
| **−** | the built-in engine will not reach 100% on exotic conjuncts; that gap must be documented per corpus id in the README's "known limitations" |

---

## 3. Decision

**Adopt (c).**

Concretely:

1. **Keep the current reorder engine as `legacy` and fix it**, starting with the reph
   `RangeError` (BASELINE §2). It stays the exact 1.x-compatible ANSI path.
2. **Add a new pure-Dart `builtin` engine** that is Unicode-in / glyph-id-out. It reads
   the font's real `cmap`, and — this is the key upgrade over 1.0.6 — reads `GSUB`
   ligature and substitution lookups so conjunct coverage comes from *the font*, not
   from a hand-maintained table. Scope it deliberately:
   * full Indic cluster segmentation and reordering (reph, pre-base matras, phalas) —
     rules we must own regardless;
   * GSUB lookup types **1 (single), 2 (multiple), 4 (ligature), 6 (chained context)**,
     which is what Bengali fonts actually use for `akhn/rphf/blwf/half/pstf/vatu/cjct/pres`;
   * GPOS types **1, 2, 4, 6** (single, pair, mark-to-base, mark-to-mark) for
     chandrabindu and matra positioning;
   * *not* the full Universal Shaping Engine, and not exotic lookup types. Anything the
     engine cannot resolve degrades to the correct Unicode sequence with default
     positioning, never to a crash.
3. **Optional `bangla_pdf_harfbuzz`** exposes the same interface backed by
   `hb_shape()`. `auto` prefers it when registered.
4. **Emit real PDF text in every mode except `legacy`**: a custom `PdfFont` subclass
   writing Type0 / Identity-H, CIDs = glyph ids, `CIDToGIDMap /Identity`, and a
   `/ToUnicode` CMap with **multi-scalar `bfchar` values** so `ক্ষ্ম` maps back to
   `<0995 09CD 09B7 09CD 09AE>`. This is what makes copy/paste exact rather than
   approximate, and it is the thing neither existing package does.
   `package:pdf`'s own `PdfUnicodeCmap` and `TtfWriter` cannot express this (AUDIT §3),
   so we need our own; both are exported and subclassable, and Apache-2.0 permits the
   fork with attribution.

### Why not (a) alone
The Indic shaper is the single hardest component and the one with the least tolerance for
"nearly right". Owning it *without* a reference implementation to differential-test
against would be reckless. Under (c) we get exactly that reference: `bangla_pdf_harfbuzz`
and the `hb-shape` CLI both produce ground-truth glyph sequences the built-in engine can
be diffed against, case by case, in CI.

### Why not (b) alone
It breaks the SDK floor, imposes a C toolchain on every consumer, and abandons web —
where 1.0.6 works today. Making the *default* install heavier and less portable in order
to fix Bangla is the wrong trade for a package whose stated identity is "lightweight,
nothing more, nothing less".

---

## 4. Consequences

* `bangla_pdf` keeps zero non-Dart dependencies and its current SDK floor.
* Two engines to maintain, and a corpus that must pass in both modes.
* The built-in engine's conjunct coverage is bounded by the GSUB lookup types we
  implement; the README must list every corpus id it still fails.
* Emitting our own Type0 font means owning a TTF subsetter keyed on glyph ids. **First
  cut may embed the font unsubsetted** (Noto Sans Bengali = 200 KB, Kalpurush Unicode
  ≈ 400 KB per PDF) and add subsetting as a follow-up minor. That must be called out in
  the README, since 1.0.6's PDFs are ~9 KB.

---

## 5. Binary-size cost of the HarfBuzz companion

**Measured on this machine:** Homebrew `libharfbuzz.0.dylib` 14.4.0, arm64, full build =
**1,235,056 bytes**. `harfbuzz_ffi` 0.5.0 compiles `harfbuzz-world.cc` with
`HB_HAS_SUBSET` and `HB_EXPERIMENTAL_API` defined — i.e. the *large* configuration,
including the subsetter, which we do not need for shaping.

**Estimated** per-architecture addition to a release app, for a shaping-only build
(`HB_LEAN`, no subset, no ICU/glib/cairo/graphite):

| platform | arch(es) | estimate |
|---|---|---|
| Android | arm64-v8a | ~450–700 KB |
| Android | + armeabi-v7a, x86_64 (split APKs mitigate) | ~1.3–2.1 MB total for a fat APK |
| iOS | arm64, statically linked, dead-strip | ~500–800 KB |
| macOS | arm64 + x86_64 universal | ~1.0–1.6 MB |
| Windows | x64 DLL | ~700 KB–1.0 MB |
| Linux | x64 .so | ~700 KB–1.0 MB |
| Web | `harfbuzzjs` WASM | ~250–400 KB gzipped, fetched at runtime |

With `harfbuzz_ffi`'s current `HB_HAS_SUBSET` build, expect roughly **1.5–2.5 MB per
architecture** instead.

> **Confidence: low.** Only the 1.23 MB Homebrew dylib is measured. The rest are
> literature estimates. Before recommending the companion in the README I want to build
> the Flutter example for each platform with and without it and report real deltas.
> Marked as an open item.

---

## 6. Rejected alternative worth recording

**Depend on `pdf_text_shaper` directly.** It would give correct shaping immediately. It
was rejected because its output model is glyph outlines plus an invisible text overlay
(AUDIT §2), which is precisely the design we intend to beat on text fidelity and file
size — and because it would make `bangla_pdf` a thin wrapper over a competitor's engine,
inheriting its no-web constraint and its Dart 3.13 floor.

---

## 7. Two decisions I need from you before Phase 3

### 7.1 What does the default do for an existing 1.x user? — **blocking**

This is the one genuine 1.x-compatibility conflict (CURRENT_STATE §7). `banglaFont:` and
`banglaStyle.font` are handed **already-transcoded ANSI text** today. A user passing
SutonnyMJ or Kalpurush-ANSI works now; the same call under a Unicode pipeline produces
garbage. The choice cannot be made from the code.

| | default for existing users | new capability reached by | risk |
|---|---|---|---|
| **A** | `legacy` — ANSI, byte-identical output to 1.0.6 apart from the crash fix | `BanglaPdf.configure(shapingMode: …)` | zero regression; correct Bangla is opt-in, so most users never get it |
| **B** | `auto` — Unicode pipeline | `shapingMode: BanglaShapingMode.legacy` | anyone passing a custom **ANSI** font breaks; anyone whose downstream tooling parses the ANSI text breaks. Needs 2.0.0 + MIGRATION.md |
| **C** | `auto`, but **sniff the supplied font** — if it has no Bengali `cmap` coverage, fall back to `legacy` for that font automatically | — | near-zero regression *and* correct-by-default; costs a font-inspection pass and one surprising-but-documented behaviour |

**My recommendation: C**, shipped as **1.1.0**, with `legacy` available as an explicit
escape hatch. It satisfies "no code changes for existing users" literally — an ANSI font
keeps the ANSI path, the default embedded font is swapped for a Unicode one and takes the
new path — and it avoids a 2.0.0. I have not implemented anything yet and will not until
you pick.

### 7.2 May I ship the reph crash fix as 1.0.7 now?

`কর্ম`, `ধর্ম`, `বর্ষ`, `পূর্ব`, `শর্ত` at the end of a Bangla run throw an uncaught
`RangeError` that aborts `pdf.save()` (BASELINE §2). The fix is bounds guards in
`_rearrangeUnicodeStr` — no behaviour change on any input that does not currently crash,
so it is a safe patch release that need not wait for Phases 2–6.
