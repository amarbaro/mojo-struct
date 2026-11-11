#!/usr/bin/env python3
"""CPython reference for bench/unpack.mojo: same buffer, same loops."""
import struct
import time
N = 1_000_000
s = struct.Struct('<hIqd')
buf = bytes(((i * 131 + 7) & 0x7F) for i in range(N * s.size))
t0 = time.perf_counter_ns()
total = 0
f = 0.0
for r in range(N):
    a, b, c, d = s.unpack_from(buf, r * s.size)
    total += a + b + c
    f += d
t1 = time.perf_counter_ns()
p = bytearray(s.size)
for r in range(N):
    s.pack_into(p, 0, r & 0x7FFF, r, r * 3, float(r))
t2 = time.perf_counter_ns()
print('python unpack_from_ns_per_record', (t1 - t0) // N, 'pack_into_ns_per_record', (t2 - t1) // N, 'check', total)
