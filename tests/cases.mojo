# Case runner for scripts/check.sh: replays tests/golden/vectors.txt, one output line per row.
from std.sys import argv
from support import replay


def main() raises:
    with open("tests/golden/vectors.txt", "r") as f:
        for line in f.read().split("\n"):
            if line.byte_length() > 0:
                print(replay(line))
