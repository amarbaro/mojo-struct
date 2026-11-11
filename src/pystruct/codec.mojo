# Pack and unpack binary data with CPython 3.14 struct semantics: format codes, byte orders,
# native alignment, and the same error texts. Values are `Value` (int, float, bool, bytes, complex).
from std.memory import bitcast
from std.math import isinf

comptime Bytes = List[UInt8]


@fieldwise_init
struct Complex(Copyable, Equatable, Movable, Writable):
    var re: Float64
    var im: Float64


@fieldwise_init
struct Value(Copyable, Movable):
    """One packed or unpacked item. A tagged struct, not a Variant: on Mojo 1.2 a Variant holding Int128
    and a List loses its tag when an outer List reallocates."""

    comptime INT: UInt8 = 0
    comptime FLOAT: UInt8 = 1
    comptime BOOL: UInt8 = 2
    comptime BYTES: UInt8 = 3
    comptime COMPLEX: UInt8 = 4
    var kind: UInt8
    var int: Int128  # INT, or BOOL as 0/1
    var re: Float64  # FLOAT, or the COMPLEX real part
    var im: Float64
    var bytes: Bytes

    @implicit
    def __init__(out self, v: Int128):
        self = Self(Self.INT, v, 0.0, 0.0, Bytes())

    @implicit
    def __init__(out self, v: Int):
        self = Self(Self.INT, Int128(v), 0.0, 0.0, Bytes())

    @implicit
    def __init__(out self, v: Float64):
        self = Self(Self.FLOAT, 0, v, 0.0, Bytes())

    @implicit
    def __init__(out self, v: Bool):
        self = Self(Self.BOOL, Int128(1) if v else Int128(0), 0.0, 0.0, Bytes())

    @implicit
    def __init__(out self, var v: Bytes):
        self = Self(Self.BYTES, 0, 0.0, 0.0, v^)

    @implicit
    def __init__(out self, v: Complex):
        self = Self(Self.COMPLEX, 0, v.re, v.im, Bytes())

comptime OVERFLOW = "OverflowError: "
"""Prefix of the errors CPython raises as OverflowError (struct.error otherwise)."""


@fieldwise_init
struct _Item(Copyable, Movable):
    var code: Int
    var count: Int  # items, or the byte length for s and p
    var offset: Int
    var size: Int  # one item


def _std(code: Int, native: Bool) -> Int:
    """Item size; 0 for a code the mode does not know."""
    if code == ord("x") or code == ord("b") or code == ord("B") or code == ord("c") or code == ord("s") or code == ord("p") or code == ord("?"):
        return 1
    if code == ord("h") or code == ord("H") or code == ord("e"):
        return 2
    if code == ord("i") or code == ord("I") or code == ord("f"):
        return 4
    if code == ord("l") or code == ord("L"):
        return 8 if native else 4
    if code == ord("q") or code == ord("Q") or code == ord("d") or code == ord("F"):
        return 8
    if code == ord("D"):
        return 16
    if native and (code == ord("n") or code == ord("N") or code == ord("P")):
        return 8
    return 0


struct Struct(Movable, Sized):
    """A compiled format string (CPython `struct.Struct`)."""

    var format: String
    var size: Int
    var items: List[_Item]
    var little: Bool
    var nvalues: Int

    def __init__(out self, format: StringSlice) raises:
        self.format = String(format)
        self.items = List[_Item]()
        self.size = 0
        self.nvalues = 0
        var b = format.as_bytes()
        var i = 0
        var mode = ord("@")
        if len(b) > 0 and (Int(b[0]) == ord("@") or Int(b[0]) == ord("=") or Int(b[0]) == ord("<") or Int(b[0]) == ord(">") or Int(b[0]) == ord("!")):
            mode = Int(b[0])
            i = 1
        var native = mode == ord("@")
        self.little = mode == ord("@") or mode == ord("=") or mode == ord("<")
        while i < len(b):
            var c = Int(b[i])
            if c == 0:
                raise Error("embedded null character")
            if c == ord(" ") or (c >= 9 and c <= 13):
                i += 1
                continue
            var count = 1
            if c >= ord("0") and c <= ord("9"):
                count = 0
                while i < len(b) and Int(b[i]) >= ord("0") and Int(b[i]) <= ord("9"):
                    if count > (Int.MAX - (Int(b[i]) - ord("0"))) // 10:
                        raise Error("total struct size too long")
                    count = count * 10 + (Int(b[i]) - ord("0"))
                    i += 1
                if i == len(b):
                    raise Error("repeat count given without format specifier")
                c = Int(b[i])
            var size = _std(c, native)
            if size == 0:
                raise Error("bad char in struct format")
            if native and size > 1 and c != ord("s") and c != ord("p"):
                var align = 4 if c == ord("F") else (8 if c == ord("D") else size)
                self.size = (self.size + align - 1) // align * align
            var bytes = count if c == ord("s") or c == ord("p") else count * size
            if bytes // size != count and c != ord("s") and c != ord("p") or self.size > Int.MAX - bytes:
                raise Error("total struct size too long")
            self.items.append(_Item(c, count, self.size, size))
            self.size += bytes
            if c != ord("x"):
                self.nvalues += 1 if c == ord("s") or c == ord("p") else count
            i += 1

    def __len__(self) -> Int:
        return self.size

    def pack(self, values: List[Value]) raises -> Bytes:
        if len(values) != self.nvalues:
            raise Error(t"pack expected {self.nvalues} items for packing (got {len(values)})")
        var out = Bytes(length=self.size, fill=0)
        self._pack(Span(out), 0, values)
        return out^

    def pack_into(self, mut buf: Bytes, offset: Int, values: List[Value]) raises:
        if len(values) != self.nvalues:
            raise Error(t"pack_into expected {self.nvalues} items for packing (got {len(values)})")
        var at = offset
        if at < 0:
            if at + self.size > 0:
                raise Error(t"no space to pack {self.size} bytes at offset {offset}")
            if at + len(buf) < 0:
                raise Error(t"offset {offset} out of range for {len(buf)}-byte buffer")
            at += len(buf)
        if len(buf) - at < self.size:
            raise Error(t"pack_into requires a buffer of at least {self.size + at} bytes for packing {self.size} bytes at offset {at} (actual buffer size is {len(buf)})")
        for j in range(at, at + self.size):
            buf[j] = 0
        self._pack(Span(buf), at, values)

    def unpack(self, buf: Span[UInt8, _]) raises -> List[Value]:
        if len(buf) != self.size:
            raise Error(t"unpack requires a buffer of {self.size} bytes")
        return self._unpack(buf, 0)

    def unpack_from(self, buf: Span[UInt8, _], offset: Int = 0) raises -> List[Value]:
        var at = offset
        if at < 0:
            if at + len(buf) < 0:
                raise Error(t"offset {offset} out of range for {len(buf)}-byte buffer")
            at += len(buf)
        if len(buf) - at < self.size:
            if offset < 0:
                raise Error(t"not enough data to unpack {self.size} bytes at offset {offset}")
            raise Error(t"unpack_from requires a buffer of at least {self.size + at} bytes for unpacking {self.size} bytes at offset {at} (actual buffer size is {len(buf)})")
        return self._unpack(buf, at)

    def iter_unpack(self, buf: Span[UInt8, _]) raises -> List[List[Value]]:
        if self.size == 0:
            raise Error("cannot iteratively unpack with a struct of length 0")
        if len(buf) % self.size != 0:
            raise Error(t"iterative unpacking requires a buffer of a multiple of {self.size} bytes")
        var out = List[List[Value]](capacity=len(buf) // self.size)
        for at in range(0, len(buf), self.size):
            out.append(self._unpack(buf, at))
        return out^

    def _pack(self, buf: Span[mut=True, UInt8, _], base: Int, values: List[Value]) raises:
        var k = 0
        for ref it in self.items:
            if it.code == ord("x"):
                continue
            if it.code == ord("s") or it.code == ord("p"):
                ref v = values[k]
                k += 1
                if not v.kind == Value.BYTES:
                    raise Error(t"argument for '{chr(Int(it.code))}' must be a bytes object")
                ref data = v.bytes
                var n = min(len(data), it.count)
                var at = base + it.offset
                if it.code == ord("p"):
                    if it.count == 0:
                        continue
                    n = min(n, it.count - 1)
                    buf[at] = UInt8(min(n, 255))
                    at += 1
                for j in range(n):
                    buf[at + j] = data[j]
                continue
            for j in range(it.count):
                _put(buf, base + it.offset + j * it.size, it.code, it.size, values[k], self.little)
                k += 1

    def _unpack(self, buf: Span[UInt8, _], base: Int) raises -> List[Value]:
        var out = List[Value](capacity=self.nvalues)
        for ref it in self.items:
            var at = base + it.offset
            if it.code == ord("x"):
                continue
            if it.code == ord("s") or it.code == ord("p"):
                var n = it.count
                if it.code == ord("p") and n > 0:
                    n = min(Int(buf[at]), n - 1)
                    at += 1
                out.append(Bytes(buf[at : at + n]))
                continue
            for j in range(it.count):
                out.append(_get(buf, at + j * it.size, it.code, it.size, self.little))
        return out^


def _raw(buf: Span[UInt8, _], at: Int, n: Int, little: Bool) -> UInt64:
    var v = UInt64(0)
    for j in range(n):
        v |= UInt64(buf[at + j if little else at + n - 1 - j]) << UInt64(8 * j)
    return v


def _store(buf: Span[mut=True, UInt8, _], at: Int, n: Int, v: UInt64, little: Bool):
    for j in range(n):
        buf[at + j if little else at + n - 1 - j] = UInt8((v >> UInt64(8 * j)) & 0xFF)


def _signed(code: Int) -> Bool:
    return code == ord("b") or code == ord("h") or code == ord("i") or code == ord("l") or code == ord("q") or code == ord("n")


def _get(buf: Span[UInt8, _], at: Int, code: Int, n: Int, little: Bool) -> Value:
    var r = _raw(buf, at, min(n, 8), little)
    if code == ord("?"):
        return Value(r != 0)
    if code == ord("c"):
        return Value(Bytes(buf[at : at + 1]))
    if code == ord("e"):
        return Value(bitcast[DType.float16](UInt16(r)).cast[DType.float64]())
    if code == ord("f"):
        return Value(_f32(UInt32(r)))
    if code == ord("d"):
        return Value(_f64(r))
    if code == ord("F"):
        return Value(Complex(_f32(UInt32(r & 0xFFFFFFFF if little else r >> 32)), _f32(UInt32(r >> 32 if little else r & 0xFFFFFFFF))))
    if code == ord("D"):
        return Value(Complex(_f64(r), _f64(_raw(buf, at + 8, 8, little))))
    var v = Int128(r)
    if _signed(code) and v >= Int128(1) << Int128(8 * n - 1):
        v -= Int128(1) << Int128(8 * n)
    return Value(v)


def _f32(bits: UInt32) -> Float64:
    return bitcast[DType.float32](bits).cast[DType.float64]()


def _f64(bits: UInt64) -> Float64:
    return bitcast[DType.float64](bits)


def _float(v: Value, what: StaticString) raises -> Float64:
    if v.kind == Value.FLOAT:
        return v.re
    if v.kind == Value.INT:
        return v.int.cast[DType.float64]()
    if v.kind == Value.BOOL:
        return 1.0 if (v.int != 0) else 0.0
    raise Error(what)


def _narrow[dt: DType](x: Float64, code: StaticString) raises -> Scalar[dt]:
    """CPython PyFloat_Pack2/4: round to nearest even; a finite x that rounds to inf overflows."""
    var y = x.cast[dt]()
    if isinf(y) and not isinf(x):
        raise Error(t"{OVERFLOW}float too large to pack with {code} format")
    return y


def _bounds(code: Int, n: Int) -> Tuple[Int128, Int128]:
    if _signed(code):
        return (-(Int128(1) << Int128(8 * n - 1)), (Int128(1) << Int128(8 * n - 1)) - 1)
    return (Int128(0), (Int128(1) << Int128(8 * n)) - 1)


def _put(buf: Span[mut=True, UInt8, _], at: Int, code: Int, n: Int, v: Value, little: Bool) raises:
    if code == ord("?"):
        var t = (v.kind == Value.BOOL and (v.int != 0)) or (v.kind == Value.INT and v.int != 0) or (v.kind == Value.FLOAT and v.re != 0.0)
        t = t or (v.kind == Value.BYTES and len(v.bytes) > 0) or (v.kind == Value.COMPLEX and (v.re != 0.0 or v.im != 0.0))
        buf[at] = UInt8(1 if t else 0)
        return
    if code == ord("c"):
        if not v.kind == Value.BYTES or len(v.bytes) != 1:
            raise Error("char format requires a bytes object of length 1")
        buf[at] = v.bytes[0]
        return
    if code == ord("F") or code == ord("D"):
        var z: Complex
        if v.kind == Value.COMPLEX:
            z = Complex(v.re, v.im)
        else:
            z = Complex(_float(v, "required argument is not a complex"), 0.0)
        if code == ord("F"):
            _store(buf, at, 4, UInt64(bitcast[DType.uint32](_narrow[DType.float32](z.re, "f") if not little else z.re.cast[DType.float32]())), little)
            _store(buf, at + 4, 4, UInt64(bitcast[DType.uint32](_narrow[DType.float32](z.im, "f") if not little else z.im.cast[DType.float32]())), little)
        else:
            _store(buf, at, 8, bitcast[DType.uint64](z.re), little)
            _store(buf, at + 8, 8, bitcast[DType.uint64](z.im), little)
        return
    if code == ord("e") or code == ord("f") or code == ord("d"):
        var x = _float(v, "required argument is not a float")
        if code == ord("e") and v.kind == Value.INT and (v.int < Int128(Int64.MIN) or v.int > Int128(Int64.MAX)):
            raise Error("int too large to convert")
        var bits: UInt64
        if code == ord("e"):
            bits = UInt64(bitcast[DType.uint16](_narrow[DType.float16](x, "e")))
        elif code == ord("f"):
            bits = UInt64(bitcast[DType.uint32](_narrow[DType.float32](x, "f")))
        else:
            bits = bitcast[DType.uint64](x)
        _store(buf, at, n, bits, little)
        return
    var i: Int128
    if v.kind == Value.INT:
        i = v.int
    elif v.kind == Value.BOOL:
        i = Int128(1) if (v.int != 0) else Int128(0)
    else:
        raise Error("required argument is not an integer")
    if code == ord("P"):
        if i < Int128(Int64.MIN) or i > (Int128(1) << 64) - 1:
            raise Error("int too large to convert")
        _store(buf, at, n, UInt64(i & 0xFFFFFFFFFFFFFFFF), little)
        return
    var lo, hi = _bounds(code, n)
    if i < lo or i > hi:
        raise Error(t"'{chr(Int(code))}' format requires {lo} <= number <= {hi}")
    _store(buf, at, n, UInt64(i & 0xFFFFFFFFFFFFFFFF), little)


def calcsize(format: StringSlice) raises -> Int:
    return Struct(format).size


def pack(format: StringSlice, values: List[Value]) raises -> Bytes:
    return Struct(format).pack(values)


def pack_into(format: StringSlice, mut buf: Bytes, offset: Int, values: List[Value]) raises:
    Struct(format).pack_into(buf, offset, values)


def unpack(format: StringSlice, buf: Span[UInt8, _]) raises -> List[Value]:
    return Struct(format).unpack(buf)


def unpack_from(format: StringSlice, buf: Span[UInt8, _], offset: Int = 0) raises -> List[Value]:
    return Struct(format).unpack_from(buf, offset)


def iter_unpack(format: StringSlice, buf: Span[UInt8, _]) raises -> List[List[Value]]:
    return Struct(format).iter_unpack(buf)
