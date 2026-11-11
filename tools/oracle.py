#!/usr/bin/env python3
"""Live CPython output for the rows the Mojo runner replays."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_vectors import evaluate
sys.stdout.reconfigure(line_buffering=True)
if sys.argv[1] == '--list':
    print('golden')
else:
    for row in Path('tests/golden/vectors.txt').read_text().splitlines():
        i, op, f, a, b, o, _, _ = row.split('\t')
        status, result = evaluate(op, f.encode().decode('unicode_escape'), a, '' if b == '-' else b, int(o))
        print('\t'.join((i, status, result)))
