#!/usr/bin/env python3
"""Diffs every compat widget's constructor against its `package:pdf` twin.

`package:bangla_pdf/widgets.dart` only works as a drop-in if each replacement
accepts exactly what the widget it replaces accepts. test/compat_test.dart
catches a *renamed* parameter, because it stops compiling; it cannot catch one
that was never added. This does.

    python3 tool/dev/check_pw_parity.py

Exits non-zero when a parameter is missing. Bump the pdf version in PW when the
dependency moves.
"""
import re, os, sys
PW = os.path.expanduser('~/.pub-cache/hosted/pub.dev/pdf-3.13.0/lib/src/widgets')
OURS = open('lib/src/compat/widgets.dart', encoding='utf-8').read()

def paramlist(src, start):
    """Balanced ( ... ) beginning at the '(' at or after `start`."""
    i = src.index('(', start); depth = 0; j = i
    while j < len(src):
        if src[j] in '([{': depth += 1
        elif src[j] in ')]}':
            depth -= 1
            if depth == 0: break
        j += 1
    return src[i+1:j]

def split_top(s):
    """Split on commas that are not inside any bracket."""
    out, depth, cur = [], 0, ''
    for ch in s:
        if ch in '([{': depth += 1
        elif ch in ')]}': depth -= 1
        if ch == ',' and depth == 0:
            out.append(cur); cur = ''
        else: cur += ch
    out.append(cur)
    return out

def names(block):
    """Top-level parameter names, positional and named alike."""
    block = block.strip()
    # Unwrap the optional/named group: the first { or [ at depth 0 opens it.
    depth, opencur = 0, None
    for i, ch in enumerate(block):
        if ch in '([': depth += 1
        elif ch in ')]': depth -= 1
        elif ch == '{' and depth == 0 and opencur is None:
            opencur = i; break
    if opencur is not None:
        # matching close brace is the last } in the list
        close = block.rindex('}')
        block = block[:opencur] + ',' + block[opencur+1:close]
    out = split_top(block)
    res = set()
    for p in out:
        p = re.sub(r'//.*', '', p).strip()
        if not p or p in '{}': continue
        p = p.split('=')[0].strip().lstrip('{').strip()
        m = re.search(r'(?:this\.|super\.)?([A-Za-z_][A-Za-z0-9_]*)\s*$', p)
        if m: res.add(m.group(1))
    return res

def find(src, decl, ctor):
    k = src.index(decl)
    return names(paramlist(src, src.index(ctor, k)))

def pwsrc(f): return open(f'{PW}/{f}', encoding='utf-8').read()

cases = [
 ('Text',        names(paramlist(pwsrc('text.dart'), pwsrc('text.dart').index('class Text extends RichText'))),
                 find(OURS, 'class Text extends pw.StatelessWidget', 'Text(')),
 ('RichText',    find(pwsrc('text.dart'), 'class RichText extends Widget', 'RichText('),
                 find(OURS, 'class RichText extends pw.StatelessWidget', 'RichText(')),
 ('TextSpan',    find(pwsrc('text.dart'), 'class TextSpan extends InlineSpan', 'TextSpan('),
                 find(OURS, 'class TextSpan extends pw.TextSpan', 'TextSpan(')),
 ('Header',      find(pwsrc('content.dart'), 'class Header extends', 'Header('),
                 find(OURS, 'class Header extends pw.StatelessWidget', 'Header(')),
 ('Paragraph',   find(pwsrc('content.dart'), 'class Paragraph extends', 'Paragraph('),
                 find(OURS, 'class Paragraph extends pw.StatelessWidget', 'Paragraph(')),
 ('Bullet',      find(pwsrc('content.dart'), 'class Bullet extends', 'Bullet('),
                 find(OURS, 'class Bullet extends pw.StatelessWidget', 'Bullet(')),
 ('Watermark',   find(pwsrc('content.dart'), 'class Watermark extends', 'Watermark('),
                 find(OURS, 'class Watermark extends pw.StatelessWidget', 'Watermark(')),
 ('Watermark.text', find(pwsrc('content.dart'), 'class Watermark extends', 'Watermark.text('),
                 find(OURS, 'class Watermark extends pw.StatelessWidget', 'Watermark.text(')),
 ('ChartLegend', find(pwsrc('chart/legend.dart'), 'class ChartLegend extends', 'ChartLegend('),
                 find(OURS, 'class ChartLegend extends pw.StatelessWidget', 'ChartLegend(')),
 ('FixedAxis',   find(pwsrc('chart/grid_axis.dart'), 'class FixedAxis<T extends num>', 'FixedAxis('),
                 find(OURS, 'class FixedAxis<T extends num>', 'FixedAxis(')),
 ('FixedAxis.fromStrings', find(pwsrc('chart/grid_axis.dart'), 'class FixedAxis<T extends num>', 'fromStrings('),
                 find(OURS, 'class FixedAxis<T extends num>', 'fromStrings(')),
 ('ChoiceField', find(pwsrc('forms.dart'), 'class ChoiceField extends', 'ChoiceField('),
                 find(OURS, 'class ChoiceField extends pw.StatelessWidget', 'ChoiceField(')),
 ('TextField',   find(pwsrc('forms.dart'), 'class TextField extends', 'TextField('),
                 find(OURS, 'class TextField extends pw.StatelessWidget', 'TextField(')),
 ('TableHelper.fromTextArray', find(pwsrc('table_helper.dart'), 'mixin TableHelper', 'fromTextArray('),
                 find(OURS, 'mixin TableHelper', 'fromTextArray(')),
]

bad = 0
for name, theirs, mine in cases:
    missing = theirs - mine
    extra = mine - theirs
    status = 'ok' if not missing else 'MISSING ' + ', '.join(sorted(missing))
    print(f'{name:26} pw={len(theirs):2} ours={len(mine):2}  {status}'
          + (f'   (extra: {sorted(extra)})' if extra else ''))
    if missing: bad += 1
print('\nRESULT:', 'FULL PARITY' if bad == 0 else f'{bad} widget(s) missing parameters')
sys.exit(1 if bad else 0)
