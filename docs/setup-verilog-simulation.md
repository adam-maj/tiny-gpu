# tiny-gpu Setup Guide for a Systems Software Engineer

This guide is written for someone who is comfortable with Linux, shells, compilers, and build systems, but is new to Verilog/SystemVerilog simulation.

It covers:

1. what this repository is doing at a high level
2. what tools are required
3. how to install them
4. the exact compatibility issues I hit on this machine
5. how to compile and run the simulations successfully

---

## 1. Mental model: what you are actually running

If you come from systems software, the easiest analogy is this:

- **SystemVerilog RTL (`src/*.sv`)** is the hardware design source code
- **`sv2v`** is a source-to-source translator that converts SystemVerilog into plain Verilog
- **`iverilog`** is the compiler/elaborator for the generated Verilog
- **`vvp`** is the simulation runtime that executes the compiled design
- **`cocotb`** is the Python test harness that plays the role of a software testbench

So the flow is roughly:

```text
SystemVerilog source
  -> sv2v
Verilog output
  -> iverilog
compiled simulation image (.vvp)
  -> vvp + cocotb Python test
simulated execution + assertions + logs
```

In this repo, cocotb acts like the “host system” for the GPU. It:

- starts the clock
- resets the DUT
- loads program memory and data memory
- writes the thread count into the device control register
- asserts `start`
- waits until `done`
- checks the output values

---

## 2. What this repository needs

From the repo's `README.md` and `Makefile`, the practical requirements are:

- Python 3
- `pip`
- `make`
- `sv2v`
- `iverilog`
- `vvp` (comes with Icarus Verilog)
- `cocotb`
- a `build/` directory

Optional:

- `gtkwave` for waveform viewing

---

## 3. Important compatibility note: cocotb version matters here

This repository's `Makefile` uses:

```bash
cocotb-config --prefix
```

That works with **cocotb 1.9.x**, but it does **not** work with cocotb 2.0.x, where `--prefix` was removed from `cocotb-config`.

### What happened on this machine

I first installed `cocotb 2.0.1`, and the repo became incompatible with the existing `Makefile`.

The working fix was to pin cocotb to:

```bash
cocotb==1.9.2
```

If you keep the current `Makefile` unchanged, **use cocotb 1.9.2**.

---

## 4. Recommended install paths

There are two reasonable setup modes.

### Option A — easiest if you have sudo

Install system packages via apt, and install cocotb with pip:

```bash
sudo apt-get update
sudo apt-get install -y iverilog gtkwave unzip curl
python3 -m pip install --user 'cocotb==1.9.2'
```

Then install `sv2v` from the official release:

```bash
mkdir -p "$HOME/.local/opt/downloads"
curl -L https://github.com/zachjs/sv2v/releases/download/v0.0.13/sv2v-Linux.zip \
  -o "$HOME/.local/opt/downloads/sv2v-Linux.zip"
unzip -o "$HOME/.local/opt/downloads/sv2v-Linux.zip" \
  -d "$HOME/.local/opt/downloads/sv2v-linux"
ln -sfn "$HOME/.local/opt/downloads/sv2v-linux/sv2v-Linux/sv2v" "$HOME/.local/bin/sv2v"
```

This is the simplest route if you control the machine.

### Option B — no sudo / user-local install only

This is what I used successfully on this machine.

---

## 5. No-sudo setup that actually worked here

### 5.1 Install cocotb in your user site-packages

```bash
python3 -m pip install --user --force-reinstall 'cocotb==1.9.2'
```

Verify:

```bash
cocotb-config --version
cocotb-config --help | head
```

Expected: version `1.9.2`, and help output should include `--prefix`.

### 5.2 Download and unpack Icarus Verilog locally

Create directories:

```bash
mkdir -p "$HOME/.local/opt/iverilog"
mkdir -p "$HOME/.local/opt/downloads"
```

Download the Ubuntu package without installing it system-wide:

```bash
cd /path/to/tiny-gpu
apt-get download iverilog
```

That produces a file like:

```text
iverilog_11.0-1.1_amd64.deb
```

Extract it into your home directory:

```bash
dpkg-deb -x ./iverilog_11.0-1.1_amd64.deb "$HOME/.local/opt/iverilog"
```

### 5.3 Fix the internal helper path for the extracted Icarus package

This matters.

When you install `iverilog` normally with apt, the package layout and hard-coded helper paths line up automatically. But when you simply extract the `.deb` under your home directory, the main `iverilog` binary still expects helper programs under a slightly different prefix.

Without this fix, `iverilog` fails like this:

```text
ivlpp: not found
ivl: not found
```

Create a compatibility symlink:

```bash
mkdir -p "$HOME/.local/opt/iverilog/usr/x86_64-linux-gnu"
ln -sfn ../lib/x86_64-linux-gnu/ivl "$HOME/.local/opt/iverilog/usr/x86_64-linux-gnu/ivl"
```

### 5.4 Download the official sv2v Linux release

```bash
curl -L https://github.com/zachjs/sv2v/releases/download/v0.0.13/sv2v-Linux.zip \
  -o "$HOME/.local/opt/downloads/sv2v-Linux.zip"

unzip -o "$HOME/.local/opt/downloads/sv2v-Linux.zip" \
  -d "$HOME/.local/opt/downloads/sv2v-linux"
```

The binary ends up here:

```text
$HOME/.local/opt/downloads/sv2v-linux/sv2v-Linux/sv2v
```

### 5.5 Export PATH for this repo session

```bash
export PATH="$HOME/.local/opt/iverilog/usr/bin:$HOME/.local/opt/downloads/sv2v-linux/sv2v-Linux:$HOME/.local/bin:$PATH"
```

Verify the full toolchain:

```bash
iverilog -V
vvp -V
sv2v --version
cocotb-config --version
```

The working versions on this machine were:

- `iverilog` 11.0
- `vvp` 11.0
- `sv2v` v0.0.13
- `cocotb` 1.9.2

---

## 6. Running the repo for the first time

From the repo root:

```bash
mkdir -p build
make test_matadd
make test_matmul
```

### What these targets do

`make test_matadd` and `make test_matmul` both do the following:

1. `make compile`
2. run `sv2v`
3. compile `build/gpu.v` with `iverilog`
4. run the compiled simulation with `vvp`
5. load the relevant cocotb Python test module

### Expected successful output

You should see cocotb output like:

```text
Running on Icarus Verilog version 11.0 (stable)
Running tests with cocotb v1.9.2
...
PASS
```

On this machine, both of these passed successfully:

- `make test_matadd`
- `make test_matmul`

One small repo oddity: `test/test_matmul.py` exports a test function named `test_matadd`, so the second run still reports `running test_matadd`. That is a naming mismatch in the repo, not an environment issue.

---

## 7. Files and outputs you should expect

### Build outputs

The build places generated artifacts in:

```text
build/
```

Important files include:

- `build/alu.v`
- `build/gpu.v`
- `build/sim.vvp`

### Log outputs

The Python logger writes execution logs under:

```text
test/logs/
```

These logs are useful when you want to inspect:

- the initial memory state
- the instruction-by-instruction trace
- final memory contents

---

## 8. What each tool is doing, in plain software-engineering terms

### `sv2v`

Think of this as a compatibility transpiler.

The source code is written in **SystemVerilog**, but the simulation compiler used here (`iverilog`) is happiest with plain Verilog in this workflow. So `sv2v` translates the source before compilation.

### `iverilog`

Think of this as the compile + elaboration step.

It takes the generated Verilog and produces a simulation image (`.vvp`) containing the hardware design.

### `vvp`

Think of this as the runtime loader / executor for the compiled simulation image.

### `cocotb`

Think of this as a Python-based integration test harness for hardware.

Instead of writing HDL testbench code, you write Python coroutines that:

- drive signals
- wait on edges or time
- observe outputs
- assert expected behavior

---

## 9. Known rough edges in this repository

These are worth knowing up front so you do not waste time blaming yourself:

1. **`build/` is not created automatically**
   - you must run `mkdir -p build`

2. **The current Makefile assumes cocotb 1.x behavior**
   - specifically `cocotb-config --prefix`
   - cocotb 2.0 breaks this assumption

3. **The `sv2v` invocation is unusual**
   - the Makefile uses:
     ```bash
     sv2v -I src/* -w build/gpu.v
     ```
   - this is not the clearest standard `sv2v` usage pattern, but it worked in this repo during validation

4. **`test_matmul.py` has a naming mismatch**
   - the module is correct
   - the exported test function name is confusing

---

## 10. Recommended shell snippet for future sessions

If you plan to work on this repo repeatedly without sudo, add something like this to your shell rc file:

```bash
export PATH="$HOME/.local/opt/iverilog/usr/bin:$HOME/.local/opt/downloads/sv2v-linux/sv2v-Linux:$HOME/.local/bin:$PATH"
```

Then open a new shell and verify:

```bash
iverilog -V
sv2v --version
cocotb-config --version
```

---

## 11. Fast sanity-check checklist

If you just want the minimum sequence to confirm the environment works:

```bash
export PATH="$HOME/.local/opt/iverilog/usr/bin:$HOME/.local/opt/downloads/sv2v-linux/sv2v-Linux:$HOME/.local/bin:$PATH"
mkdir -p build
cocotb-config --version
iverilog -V
sv2v --version
make test_matadd
make test_matmul
```

If both tests pass, your local simulation environment is usable.

---

## 12. Where to look next if you are new to RTL

If you want to understand the code after setup, read in this order:

1. `README.md` — project overview and architecture explanation
2. `src/gpu.sv` — top-level module
3. `src/core.sv` — per-core composition
4. `src/scheduler.sv` — control flow and execution stages
5. `test/helpers/setup.py` — how software launches the design
6. `test/test_matadd.py` — the simplest end-to-end example

That order maps well to a systems engineer’s instincts: start with the top-level architecture, then look at orchestration, then execution, then the test harness.
