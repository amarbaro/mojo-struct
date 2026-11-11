# Replays every golden row against the CPython result stored in the file: no Python needed.
from std.testing import assert_true
from support import replay


def main() raises:
    var rows = 0
    var errors = 0
    var bad = 0
    with open("tests/golden/vectors.txt", "r") as f:
        for line in f.read().split("\n"):
            if line.byte_length() == 0:
                continue
            var c = line.split("\t")
            var want = String(c[0]) + "\t" + String(c[6]) + "\t" + String(c[7])
            var got = replay(line)
            if got != want:
                bad += 1
                if bad <= 5:
                    print("FAIL row", c[0], "want", want, "got", got)
            rows += 1
            errors += 1 if c[6] == "err" else 0
    assert_true(bad == 0)
    assert_true(rows > 5000 and errors > 1000)
    print("PASS goldens", rows, "errors", errors)
