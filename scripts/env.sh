#!/usr/bin/env bash
# Source this file to use the repo-local toolchain (iverilog, sv2v, cocotb)
# instead of relying on system-wide installs:
#
#   source scripts/env.sh
#   make test_all
#
# Re-run scripts/setup.sh first if .tools/ or .venv/ don't exist yet.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -d "$REPO_ROOT/.tools/iverilog/usr/bin" ]; then
    export PATH="$REPO_ROOT/.tools/iverilog/usr/bin:$PATH"
fi
if [ -d "$REPO_ROOT/.tools/sv2v/sv2v-Linux" ]; then
    export PATH="$REPO_ROOT/.tools/sv2v/sv2v-Linux:$PATH"
fi
if [ -d "$REPO_ROOT/.venv/bin" ]; then
    export PATH="$REPO_ROOT/.venv/bin:$PATH"
fi

# iverilog's Ubuntu package looks for its target/system libs under a
# gnu-triplet directory name; the .deb ships them under lib/x86_64-linux-gnu.
IVL_DIR="$REPO_ROOT/.tools/iverilog/usr/lib/x86_64-linux-gnu/ivl"
IVL_LINK="$REPO_ROOT/.tools/iverilog/usr/x86_64-linux-gnu/ivl"
if [ -d "$IVL_DIR" ] && [ ! -e "$IVL_LINK" ]; then
    mkdir -p "$(dirname "$IVL_LINK")"
    ln -sfn "../lib/x86_64-linux-gnu/ivl" "$IVL_LINK"
fi

# cocotb needs libpython at runtime; point at any system Python that ships it.
for candidate in \
    "$HOME/anaconda3/lib" \
    "/usr/lib/x86_64-linux-gnu"
do
    if ls "$candidate"/libpython3*.so* >/dev/null 2>&1; then
        export LD_LIBRARY_PATH="$candidate:$LD_LIBRARY_PATH"
        break
    fi
done

echo "tiny-gpu local toolchain environment loaded."
echo "  iverilog: $(command -v iverilog || echo NOT FOUND)"
echo "  sv2v:     $(command -v sv2v || echo NOT FOUND)"
echo "  python:   $(command -v python || echo NOT FOUND)"
