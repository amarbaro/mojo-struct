# Behaviour of the typed API that the golden rows cannot show.
from std.testing import assert_equal, assert_true, assert_raises
from pystruct import Struct, Value, Complex, Bytes, calcsize, pack, unpack, iter_unpack, OVERFLOW


def main() raises:
    var s = Struct("<hq")
    assert_equal(len(s), 10)
    assert_equal(s.format, "<hq")
    var b = s.pack([Value(-2), Value(Int128(1) << 62)])
    var v = s.unpack(Span(b))
    assert_equal(v[0].int, -2)
    assert_true(v[1].kind == Value.INT and v[1].int == Int128(1) << 62)
    var z = unpack("<D", Span(pack("<D", [Value(Complex(1.5, -2.0))])))
    assert_true(z[0].kind == Value.COMPLEX and z[0].re == 1.5 and z[0].im == -2.0)
    with assert_raises(contains=OVERFLOW):
        _ = pack("<e", [Value(1e10)])
    with assert_raises(contains="bad char in struct format"):
        _ = calcsize("<n")
    assert_equal(len(iter_unpack("<H", Span(Bytes(length=6, fill=1)))), 3)
    print("PASS api")
