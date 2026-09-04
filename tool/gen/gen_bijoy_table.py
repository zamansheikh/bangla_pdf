#!/usr/bin/env python3
"""Generates lib/src/extract/bijoy_table.dart by inverting the forward
Unicode -> Bijoy ANSI map in lib/src/utils/unicode_mapper.dart.

Run from the package root:  python3 tool/gen/gen_bijoy_table.py
"""
import re

src = open('lib/src/utils/unicode_mapper.dart').read()
body = src.split('_conversionMap = {', 1)[1]
pairs = []
for line in body.split('\n'):
    if line.strip().startswith('//'):
        continue
    m = re.search(r'"((?:[^"\\]|\\.)*)"\s*:\s*"((?:[^"\\]|\\.)*)"', line)
    if m:
        uni, ansi = m.group(1), m.group(2)
        pairs.append((uni.replace('\\$', '$'), ansi.replace('\\$', '$')))

inverse = {}
for uni, ansi in pairs:
    inverse.setdefault(ansi, uni)

# Longest ANSI key first: the forward direction applied replacements in
# insertion order and shadowed 7 of its own entries; sorting by length makes
# the reverse direction unambiguous.
ordered = sorted(inverse.items(), key=lambda kv: (-len(kv[0]), kv[0]))

def esc(s):
    out = s.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$')
    return out

lines = [
    "// GENERATED FILE - do not edit by hand.",
    "//",
    "// Bijoy ANSI -> Unicode, inverted from the forward table in",
    "// lib/src/utils/unicode_mapper.dart. Regenerate with:",
    "//   python3 tool/gen/gen_bijoy_table.py",
    "",
    "/// Bijoy/ANSI byte sequences mapped back to Unicode Bangla.",
    "///",
    "/// Ordered longest key first so a greedy matcher never takes a short key",
    "/// that is a prefix of a longer one.",
    "const List<(String, String)> kBijoyToUnicode = <(String, String)>[",
]
for ansi, uni in ordered:
    lines.append(f"  ('{esc(ansi)}', '{esc(uni)}'),")
lines.append('];')
lines.append('')

open('lib/src/extract/bijoy_table.dart', 'w').write('\n'.join(lines))
print(f"{len(ordered)} entries written")
