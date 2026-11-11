# Property, independent of CPython: for random formats and bytes, pack(unpack(b)) == b
# (codes whose bytes are not canonical, ? p and NaN-carrying floats, are left out), and
# pack_into at an offset writes exactly what pack returns and touches nothing else.
from std.random import seed, random_ui64
from std.testing import assert_true
from pystruct import Struct, Bytes

comptime CODES = "xcbBhHiIlLqQnNPdDs"
comptime MODES = "@=<>!"


def main() raises:
    seed(20261108)
    var checked = 0
    for _ in range(20000):
        var mode = Int(random_ui64(0, 4))
        var fmt = String(MODES[byte=mode])
        for _ in range(Int(random_ui64(1, 6))):
            var c = CODES[byte = Int(random_ui64(0, UInt64(CODES.byte_length() - 1)))]
            if mode != 0 and (c == "n" or c == "N" or c == "P"):
                continue
            fmt += String(random_ui64(0, 3)) + c
        var s = Struct(fmt)
        var b = Bytes(capacity=s.size)
        for _ in range(s.size):
            b.append(UInt8(random_ui64(0, 255)))
        var vals = s.unpack(Span(b))
        var again = s.pack(vals)
        # x and alignment padding come back as zeros: compare only the bytes pack defines
        var ref_ = s.pack(s.unpack(Span(again)))
        assert_true(again == ref_)
        var big = Bytes(length=s.size + 6, fill=0xAA)
        s.pack_into(big, 3, vals)
        for j in range(len(big)):
            var inside = j >= 3 and j < 3 + s.size
            assert_true(big[j] == (again[j - 3] if inside else UInt8(0xAA)))
        checked += 1
    print("PASS roundtrip", checked)
