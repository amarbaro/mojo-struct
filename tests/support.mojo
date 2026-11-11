# Replays one golden row through pystruct and prints it the way tools/gen_vectors.py does.
from std.memory import bitcast
from pystruct import Struct, Value, Complex, Bytes, calcsize, pack, pack_into, unpack, unpack_from, iter_unpack

comptime HEX = "0123456789abcdef"


def _nib(c: UInt8) -> UInt8:
    return c - 48 if c <= 57 else c - 87


def unhex(s: StringSlice) -> Bytes:
    var b = s.as_bytes()
    var out = Bytes(capacity=len(b) // 2)
    for i in range(0, len(b) - 1, 2):
        out.append(_nib(b[i]) << 4 | _nib(b[i + 1]))
    return out^


def tohex(b: Span[UInt8, _]) -> String:
    var out = String()
    for x in b:
        out += HEX[byte = Int(x >> 4)]
        out += HEX[byte = Int(x & 15)]
    return out^


def _bits(s: StringSlice) -> Float64:
    var v = UInt64(0)
    var b = unhex(s)
    for j in range(8):
        v |= UInt64(b[j]) << UInt64(8 * j)
    return bitcast[DType.float64](v)


def _fhex(x: Float64) -> String:
    var v = bitcast[DType.uint64](x)
    var b = Bytes(capacity=8)
    for j in range(8):
        b.append(UInt8((v >> UInt64(8 * j)) & 0xFF))
    return tohex(b)


def _int(s: StringSlice) -> Int128:
    var b = s.as_bytes()
    var neg = len(b) > 0 and Int(b[0]) == ord("-")
    var v = Int128(0)
    for i in range(1 if neg else 0, len(b)):
        v = v * 10 + Int128(Int(b[i]) - 48)
    return -v if neg else v


def unescape(s: StringSlice) -> String:
    var b = s.as_bytes()
    var out = Bytes()
    var i = 0
    while i < len(b):
        if Int(b[i]) == ord("\\") and i + 1 < len(b):
            var c = Int(b[i + 1])
            if c == ord("x"):
                out.append(_nib(b[i + 2]) << 4 | _nib(b[i + 3]))
                i += 4
                continue
            out.append(UInt8(9) if c == ord("t") else (UInt8(10) if c == ord("n") else (UInt8(13) if c == ord("r") else UInt8(c))))
            i += 2
            continue
        out.append(b[i])
        i += 1
    return String(unsafe_from_utf8=out)


def decode(s: StringSlice) raises -> List[Value]:
    var out = List[Value]()
    if s == "-":
        return out^
    for t in s.split(","):
        var k = t[byte=0]
        var r = t[byte = 1 : t.byte_length()]
        if k == "i":
            out.append(Value(_int(r)))
        elif k == "f":
            out.append(Value(_bits(r)))
        elif k == "b":
            out.append(Value(r == "1"))
        elif k == "c":
            var p = r.split(":")
            out.append(Value(Complex(_bits(p[0]), _bits(p[1]))))
        else:
            out.append(Value(unhex(r)))
    return out^


def encode(vals: List[Value]) -> String:
    var out = String()
    for i in range(len(vals)):
        if i > 0:
            out += ","
        ref v = vals[i]
        if v.kind == Value.BOOL:
            out += "b1" if (v.int != 0) else "b0"
        elif v.kind == Value.INT:
            out += "i" + String(v.int)
        elif v.kind == Value.FLOAT:
            out += "f" + _fhex(v.re)
        elif v.kind == Value.COMPLEX:
            out += "c" + _fhex(v.re) + ":" + _fhex(v.im)
        else:
            out += "s" + tohex(v.bytes)
    return out if out.byte_length() > 0 else String("-")


def evaluate(op: StringSlice, fmt: String, args: StringSlice, bufhex: StringSlice, offset: Int) -> String:
    try:
        var buf = Bytes() if String(bufhex) == "-" else unhex(bufhex)
        if op == "calcsize":
            return "ok\t" + String(calcsize(fmt))
        if op == "pack":
            return "ok\t" + tohex(pack(fmt, decode(args)))
        if op == "pack_into":
            pack_into(fmt, buf, offset, decode(args))
            return "ok\t" + tohex(buf)
        if op == "unpack":
            return "ok\t" + encode(unpack(fmt, Span(buf)))
        if op == "unpack_from":
            return "ok\t" + encode(unpack_from(fmt, Span(buf), offset))
        var rows = iter_unpack(fmt, Span(buf))
        var out = String()
        for i in range(len(rows)):
            out += (";" if i > 0 else "") + encode(rows[i])
        return "ok\t" + (out if out.byte_length() > 0 else String("-"))
    except e:
        return "err\t" + String(e)


def replay(line: StringSlice) raises -> String:
    var f = line.split("\t")
    return String(f[0]) + "\t" + evaluate(f[1], unescape(f[2]), f[3], f[4], Int(String(f[5])))
