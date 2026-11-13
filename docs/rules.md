# rules

What broke -> the rule.

- ci.sh skipped `uv python install 3.14` when MOJO= was set (the matrix nightly cell), so the oracle fell back to the runner's Python 3.12, which words errors differently; red on GitHub only (mojo-libs #2/#3) -> the oracle interpreter is installed and pinned on every path through ci.sh, never a silent fallback; a repro must remove the pinned version (empty UV_PYTHON_INSTALL_DIR), not only shadow python3.
