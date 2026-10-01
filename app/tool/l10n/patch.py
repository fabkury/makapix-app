"""Exact-match source patcher + message adder for the i18n extraction (docs/i18n/PLAN.md).

    python tool/l10n/patch.py <patchfile.py>
    flutter gen-l10n

The patch file is Python. It may call:

    patch(path, [(old, new), ...])
        Edit a source file under app/. Each `old` must occur exactly once; pass
        (old, new, n) when it legitimately occurs n times. Line endings are preserved.

    imp(path, import_line, after=None)
        Add an import line to a Dart file if it is not there yet (after the line `after`,
        or after the last existing import).

    m(key, description, en, es, pt, fr, de, ru, ja, zh, **placeholders)
        Add one message in all eight languages. placeholders: name='int' | 'String' |
        'num' | {'type': ..., 'format': ...}. A key that already exists with the same
        English text is left alone; with different text it is an error.

Write patch files with raw strings (r'''...'''). Nothing is written unless every
replacement in the file applies and every ARB stays valid JSON.
"""
import json, os, re, sys

APP = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
LOCALES = ['en', 'es', 'pt', 'fr', 'de', 'ru', 'ja', 'zh']
_pending = {}   # full path -> (crlf, text)
_msgs = []      # (key, meta, {locale: text})


def _load(path):
    full = os.path.join(APP, path)
    if full not in _pending:
        b = open(full, 'rb').read()
        _pending[full] = (b'\r\n' in b, b.decode('utf-8').replace('\r\n', '\n'))
    return full


def patch(path, pairs):
    full = _load(path)
    crlf, s = _pending[full]
    for p in pairs:
        old, new = p[0], p[1]
        want = p[2] if len(p) > 2 else 1
        got = s.count(old)
        if got != want:
            sys.exit('%s: expected %d occurrence(s), found %d:\n%s' % (path, want, got, old))
        s = s.replace(old, new)
    _pending[full] = (crlf, s)


def imp(path, import_line, after=None):
    full = _load(path)
    crlf, s = _pending[full]
    if import_line in s:
        return
    lines = s.split('\n')
    at = None
    for i, line in enumerate(lines):
        if after is not None and line.strip() == after.strip():
            at = i
            break
        if after is None and line.startswith('import '):
            at = i
    if at is None:
        sys.exit('%s: no place found for %s' % (path, import_line))
    lines.insert(at + 1, import_line)
    _pending[full] = (crlf, '\n'.join(lines))


def m(key, description, en, es, pt, fr, de, ru, ja, zh, **placeholders):
    meta = {'description': description}
    if placeholders:
        meta['placeholders'] = {
            k: (v if isinstance(v, dict) else {'type': v}) for k, v in placeholders.items()}
    if not re.match(r'^[a-z][A-Za-z0-9]*$', key):
        sys.exit('bad key %r' % key)
    _msgs.append((key, meta, dict(zip(LOCALES, [en, es, pt, fr, de, ru, ja, zh]))))


def _append(locale, entries):
    """entries: list of (key, text, meta-or-None)."""
    path = os.path.join(APP, 'lib', 'l10n', 'app_%s.arb' % locale)
    src = open(path, encoding='utf-8').read()
    existing = json.loads(src)
    out = []
    for key, text, meta in entries:
        if key in existing:
            if existing[key] != text:
                sys.exit('%s: key %s already exists with different text:\n  %r\n  %r'
                         % (locale, key, existing[key], text))
            continue
        existing[key] = text
        row = '  %s: %s' % (json.dumps(key), json.dumps(text, ensure_ascii=False))
        if meta is not None:
            row += ',\n  %s: %s' % (json.dumps('@' + key), json.dumps(meta, ensure_ascii=False))
        out.append(row)
    if not out:
        return None
    body = src.rstrip()
    assert body.endswith('}')
    body = body[:-1].rstrip() + ',\n' + ',\n'.join(out) + '\n}\n'
    json.loads(body)
    return path, body


def _flush():
    writes = []
    seen = set()
    for key, _, _ in _msgs:
        if key in seen:
            sys.exit('key %s added twice in this patch' % key)
        seen.add(key)
    for locale in LOCALES:
        w = _append(locale, [(k, t[locale], meta if locale == 'en' else None) for k, meta, t in _msgs])
        if w:
            writes.append(w)
    for path, body in writes:
        open(path, 'w', encoding='utf-8', newline='\n').write(body)
    for full, (crlf, s) in _pending.items():
        if crlf:
            s = s.replace('\n', '\r\n')
        open(full, 'wb').write(s.encode('utf-8'))
    print('patched %d file(s), %d message(s)' % (len(_pending), len(_msgs)))


if __name__ == '__main__':
    exec(compile(open(sys.argv[1], encoding='utf-8').read(), sys.argv[1], 'exec'))
    _flush()
