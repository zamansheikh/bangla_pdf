# Font fixtures

Test-only. Not published — `test/fixtures/` is in `.pubignore`.

| file | what it is | used for |
|---|---|---|
| `Kalpurush-Unicode.ttf` | Kalpurush, full Unicode build (586 glyphs, `beng`/`bng2` GSUB). OFL 1.0, no Reserved Font Name. | the source the bundled font is subsetted from |
| `Kalpurush-Subset.ttf` | the subset that is actually embedded in the package | differential testing against `hb-shape` |
| `Kalpurush-ANSI.ttf` | the legacy 8-bit Bijoy build. Byte-identical to the copy embedded since 1.0.x. | verifying `BanglaShapingMode.legacy` |
| `NotoSansBengali-Regular.ttf` | Noto Sans Bengali 3.011, OFL 1.1 | second-font validation (98% vs HarfBuzz) |
| `NotoSerifBengali-Regular.ttf` | Noto Serif Bengali 3.000, OFL 1.1 | third-font validation (91% vs HarfBuzz) |
| `NotoSansBengali-OFL.txt` | OFL 1.1 text for the two Noto fonts | licence record |

## Which fonts the package actually embeds

Two, both Kalpurush, for different pipelines:

| embedded as | font | size | why it is needed |
|---|---|---|---|
| `lib/src/core/unicode_font_data.dart` | Kalpurush Unicode, subsetted | 121 KB | the default. Shaped with its own GSUB/GPOS. Same typeface 1.0.x rendered, so upgrading changes correctness, not appearance. |
| `lib/src/core/default_font_data.dart` | Kalpurush ANSI | 113 KB | only used by `BanglaShapingMode.legacy`, which exists so 1.0.x users can get byte-identical Bijoy output. Dropping it would break that guarantee. |

Both are Kalpurush, so the package has one typeface and two encodings of it.
The ANSI copy could be removed in a 2.0 that drops legacy mode; until then it is
load-bearing for backward compatibility.

## Regenerating the bundled subset

```bash
hb-subset --unicodes=20-7E,A0-FF,964-965,980-9FE,200C-200D,2010-2015,2018-201D,2022,2026,20B9,25CC \
          --layout-features='*' --no-hinting --name-IDs='*' \
          --output-file=Kalpurush-Subset.ttf Kalpurush-Unicode.ttf
```

Then base64 it into `lib/src/core/unicode_font_data.dart`; the header comment in
that file carries the same command.
