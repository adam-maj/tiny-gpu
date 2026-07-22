#!/usr/bin/env bash
# One-time local setup: downloads iverilog + sv2v into .tools/ and creates a
# Python venv with cocotb + aiohttp in .venv/, without requiring sudo.
#
#   bash scripts/setup.sh
#   source scripts/env.sh
#   make test_all
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

mkdir -p .tools build

if [ ! -d .tools/iverilog/usr/bin ]; then
    echo "==> Fetching Icarus Verilog (.deb, no sudo needed)"
    (cd .tools && apt-get download iverilog && dpkg-deb -x iverilog_*.deb iverilog)
fi

if [ ! -f .tools/sv2v/sv2v-Linux/sv2v ]; then
    echo "==> Fetching sv2v v0.0.13"
    curl -L https://github.com/zachjs/sv2v/releases/download/v0.0.13/sv2v-Linux.zip -o .tools/sv2v.zip
    unzip -o .tools/sv2v.zip -d .tools/sv2v
fi

if [ ! -d .venv ]; then
    echo "==> Creating Python venv"
    python3 -m venv .venv
fi

echo "==> Installing Python requirements"
.venv/bin/pip install -q --upgrade pip
.venv/bin/pip install -q -r requirements.txt

echo "==> Setup complete. Run: source scripts/env.sh && make test_all"
