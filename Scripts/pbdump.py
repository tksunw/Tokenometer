#!/usr/bin/env python3
"""Schema-less protobuf dump. Usage: pbdump.py <file> | pbdump.py --sqlite <db> <idx>"""
import sys, sqlite3

def varint(b, i):
    r = s = 0
    while True:
        c = b[i]; i += 1
        r |= (c & 0x7F) << s; s += 7
        if not c & 0x80: return r, i

def parse(b):
    i, out = 0, []
    while i < len(b):
        key, i = varint(b, i); f, w = key >> 3, key & 7
        if w == 0: v, i = varint(b, i); out.append((f, 'v', v))
        elif w == 1: out.append((f, '64', int.from_bytes(b[i:i+8], 'little'))); i += 8
        elif w == 5: out.append((f, '32', int.from_bytes(b[i:i+4], 'little'))); i += 4
        elif w == 2:
            n, i = varint(b, i); out.append((f, 'b', b[i:i+n])); i += n
        else: raise ValueError(f"wire {w} at {i}")
    return out

def dump(b, path='', depth=0, maxdepth=4):
    try: fields = parse(b)
    except Exception: return False
    for f, w, v in fields:
        p = f"{path}.{f}" if path else str(f)
        if w == 'b':
            sub = None
            if v and depth < maxdepth:
                try:
                    sub = parse(v)
                except Exception:
                    sub = None
            if sub is not None and len(v) > 1 and all(isinstance(x[0], int) and 0 < x[0] < 10000 for x in sub):
                dump(v, p, depth + 1, maxdepth)
            else:
                try: s = v.decode('utf-8'); print(f"{p} str {s[:60]!r}")
                except UnicodeDecodeError: print(f"{p} bytes[{len(v)}]")
        else:
            print(f"{p} {w} {v}")
    return True

if sys.argv[1] == '--sqlite':
    row = sqlite3.connect(sys.argv[2]).execute('select data from gen_metadata where idx=?', (int(sys.argv[3]),)).fetchone()
    dump(row[0])
else:
    dump(open(sys.argv[1], 'rb').read())
