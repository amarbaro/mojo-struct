from pystruct import Struct, Value

def main() raises:
    var header = Struct("<4sIHH")
    var raw = header.pack([Value(List[UInt8]("RIFF".as_bytes())), Value(36), Value(1), Value(2)])
    var fields = header.unpack(Span(raw))
    print(header.size, fields[1].int, fields[3].int)
