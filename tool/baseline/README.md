# Phase 1 baseline harness

Runs the **unmodified** `bangla_pdf` 1.0.6 transform so its behaviour can be measured
without touching `lib/`. Nothing here is part of the published package.

| file | what it does |
|---|---|
| `mapper_106_snapshot.dart` | verbatim snapshot of `lib/src/utils/unicode_mapper.dart` with the `part of` directive removed. **Do not edit** — regenerate with `tail -n +2 lib/src/utils/unicode_mapper.dart` |
| `run_106_mapper.dart` | runs a corpus JSON through `BanglaUnicodeMapper.encodeANSI`, emits per-case output/hex/exception |
| `reph_crash_probe.dart` | reproduces `FixingUtils.getAutoLocalizedSpans`' run-splitting regex to isolate the reph `RangeError` |
| `ttfinfo.py` | pure-stdlib TTF inspector: name records, `cmap` coverage, `GSUB`/`GPOS` presence, features, lookup counts |

```bash
dart run tool/baseline/run_106_mapper.dart docs/baseline/phase1_probe_cases.json
dart run tool/baseline/reph_crash_probe.dart
python3 tool/baseline/ttfinfo.py path/to/font.ttf
```

Results are committed under [`docs/baseline/`](../../docs/baseline) and written up in
[`docs/BASELINE.md`](../../docs/BASELINE.md).
