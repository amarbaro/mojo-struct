#!/usr/bin/env python3
"""Deterministic CPython 3.14 struct vectors. Row: index, op, format, args, buffer hex, offset, status, result.
Values: i<int> f<double bits hex> b0|b1 s<bytes hex> c<re bits>:<im bits>; '-' = none."""
import math
import random
import struct
from pathlib import Path

MODES = ('', '@', '=', '<', '>', '!')
INTS = 'bBhHiIlLqQnNP'
CODES = 'xcbB?hHiIlLqQnNPefdFDsp'


def fbits(x):
    return struct.pack('<d', x).hex()


def enc(v):
    if isinstance(v, bool):
        return 'b1' if v else 'b0'
    if isinstance(v, int):
        return f'i{v}'
    if isinstance(v, float):
        return 'f' + fbits(v)
    if isinstance(v, complex):
        return f'c{fbits(v.real)}:{fbits(v.imag)}'
    return 's' + bytes(v).hex()


def dec(t):
    k, r = t[0], t[1:]
    if k == 'i':
        return int(r)
    if k == 'f':
        return struct.unpack('<d', bytes.fromhex(r))[0]
    if k == 'b':
        return r == '1'
    if k == 'c':
        a, b = r.split(':')
        return complex(dec('f' + a), dec('f' + b))
    return bytes.fromhex(r)


def encs(vals):
    return ','.join(map(enc, vals)) or '-'


def decs(s):
    return [] if s == '-' else [dec(t) for t in s.split(',')]


def evaluate(op, fmt, args, buf, offset):
    try:
        if op == 'calcsize':
            return 'ok', str(struct.calcsize(fmt))
        if op == 'pack':
            return 'ok', struct.pack(fmt, *decs(args)).hex()
        if op == 'pack_into':
            b = bytearray(bytes.fromhex(buf))
            struct.pack_into(fmt, b, offset, *decs(args))
            return 'ok', b.hex()
        if op == 'unpack':
            return 'ok', encs(struct.unpack(fmt, bytes.fromhex(buf)))
        if op == 'unpack_from':
            return 'ok', encs(struct.unpack_from(fmt, bytes.fromhex(buf), offset))
        return 'ok', ';'.join(encs(t) for t in struct.iter_unpack(fmt, bytes.fromhex(buf))) or '-'
    except OverflowError as e:
        return 'err', f'OverflowError: {e}'
    except struct.error as e:
        return 'err', str(e)


def bounds(mode, c):
    n = struct.calcsize(mode + c)
    if c == 'P' or c.isupper():
        return 0, 2 ** (8 * n) - 1
    return -2 ** (8 * n - 1), 2 ** (8 * n - 1) - 1


def native_ok(mode, c):
    return c not in 'nNP' or mode in ('', '@')


FLOATS = [0.0, -0.0, 1.0, -1.5, math.inf, -math.inf, math.nan, -math.nan, 5e-324, 2.2250738585072014e-308,
          1.7976931348623157e308, 3.4028234663852886e38, 3.4028235677973366e38, 3.402823669209385e38, 1.401298464324817e-45,
          65504.0, 65519.0, 65519.99, 65520.0, 6.1e-05, 5.960464477539063e-08, 2.98023223876953125e-08,
          2.9802322387695312e-08, 1e300, 1 + 2 ** -11, 1 + 3 * 2 ** -11, 1 + 2 ** -24, 1 + 3 * 2 ** -24, 0.1, 1 / 3]


def rows(rng):
    out = []
    add = lambda *r: out.append(r)
    fmts = ['', ' ', 'i ', ' i', '\t<i', 'i\ti', '\ti', 'i\n\x0bh', 'i\x0c\rH', '<n', '4', '<3', 'x3', 'ii z', 'i\0', '=P', '!N', '@ci', '@ic', '<ci', '2i4x', '0s',
            '10000000000000000000s', '999999999999999999i', '9223372036854775807x', '4611686018427387904i', '@c0i', '3x2c',
            '@bhilqnNPefdFD', '<bhilqefdFD', '@?', '5p', '0p', 'Z', '<<i', '@ce', '@cF', '@cD', '@cd', '@hP']
    for f in fmts:
        add('calcsize', f, '-', '', 0)
    for _ in range(300):
        f = rng.choice(MODES) + ''.join(rng.choice(['', str(rng.randint(0, 4))]) + rng.choice(CODES + 'zZ ') for _ in range(rng.randint(0, 5)))
        add('calcsize', f, '-', '', 0)
    for m in MODES:
        for c in INTS:
            if not native_ok(m, c):
                add('pack', m + c, encs([1]), '', 0)
                continue
            lo, hi = bounds(m, c)
            for v in (lo - 1, lo, lo + 1, 0, hi - 1, hi, hi + 1, -1, 2 ** 100, True, False):
                add('pack', m + c, encs([v]), '', 0)
            for v in (1.0, b'a', 1j):
                add('pack', m + c, encs([v]), '', 0)
            for _ in range(6):
                add('pack', m + c, encs([rng.randint(lo, hi)]), '', 0)
        for c in 'efd':
            for v in FLOATS + [7, True, -(2 ** 70), b'x', 1j]:
                add('pack', m + c, encs([v]), '', 0)
            for _ in range(20):
                add('pack', m + c, encs([struct.unpack('<d', rng.randbytes(8))[0]]), '', 0)
        for c in 'FD':
            for v in [1 + 2j, complex(math.inf, -0.0), complex(1e300, 1), complex(1, 1e300), 2.5, 3, True, b'x']:
                add('pack', m + c, encs([v]), '', 0)
        for v in (True, False, 0, 5, 0.0, math.nan, b'', b'a', 0j, 1j):
            add('pack', m + '?', encs([v]), '', 0)
        for v in (b'a', b'', b'ab', 1, True):
            add('pack', m + 'c', encs([v]), '', 0)
        for n in (0, 1, 2, 3, 5, 256, 300):
            for d in (b'', b'ab', b'abcdef', b'z' * 300, 1):
                add('pack', f'{m}{n}s', encs([d]), '', 0)
                add('pack', f'{m}{n}p', encs([d]), '', 0)
        add('pack', m + 'ii', encs([1]), '', 0)
        add('pack', m + 'ii', encs([1, 2, 3]), '', 0)
        add('pack', m + '3x', '-', '', 0)
    for _ in range(400):
        m = rng.choice(MODES)
        f = m + ''.join(rng.choice(['', str(rng.randint(0, 3))]) + rng.choice([c for c in CODES if native_ok(m, c)]) for _ in range(rng.randint(1, 5)))
        size = struct.calcsize(f)
        buf = rng.randbytes(size)
        add('unpack', f, '-', buf.hex(), 0)
        add('unpack', f, '-', rng.randbytes(max(0, size + rng.choice([-1, 1]))).hex(), 0)
        big = rng.randbytes(size + rng.randint(0, 9))
        add('unpack_from', f, '-', big.hex(), rng.randint(-len(big) - 3, len(big) + 3))
        add('iter_unpack', f, '-', rng.randbytes(size * rng.randint(0, 4) + rng.choice([0, 0, 1])).hex(), 0)
        vals = list(struct.unpack(f, buf))
        add('pack', f, encs(vals), '', 0)
        b = rng.randbytes(size + rng.randint(0, 6))
        add('pack_into', f, encs(vals), b.hex(), rng.randint(-len(b) - 3, len(b) + 3))
    for f, b, o in [('i', 'aabbcc', 0), ('i', '0011223344556677', 6), ('i', '00112233', -5), ('i', '0011223344556677', -4),
                    ('i', '00112233', -1), ('<h', '', 0), ('', '', 0), ('', '00', 1), ('', '00', 2)]:
        add('unpack_from', f, '-', b, o)
    for f in ('', '0s', 'x', 'i'):
        add('iter_unpack', f, '-', '', 0)
    for o in (10, -11, 2, -2, -4, 0, -1, 4):
        add('pack_into', 'i', encs([1]), '00000000', o)
    add('pack_into', 'ii', encs([1]), '0000000000000000', 0)
    return out


def main():
    rng = random.Random(20261107)
    lines = []
    for i, (op, f, a, b, o) in enumerate(rows(rng)):
        status, result = evaluate(op, f, a, b, o)
        lines.append('\t'.join((str(i), op, f.encode('unicode_escape').decode(), a, b or '-', str(o), status, result)))
    Path('tests/golden').mkdir(parents=True, exist_ok=True)
    Path('tests/golden/vectors.txt').write_text('\n'.join(lines) + '\n')
    print(len(lines), 'vectors')


if __name__ == '__main__':
    main()
