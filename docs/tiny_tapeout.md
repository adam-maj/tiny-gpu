# Tiny Tapeout 7 Adapter

`src/tt/tt_um_tiny_gpu.sv` wraps a minimal tiny-gpu configuration (**1 core,
4 threads/block, 1 data channel, 1 program channel**) behind the standard
[Tiny Tapeout](https://tinytapeout.com/) top-level interface, so it can be
fit onto a shared TT7 shuttle die (24 usable I/Os) alongside everyone else's
designs.

> **Scope note:** this is silicon-flow scaffolding validated only in
> simulation (see `test/test_tt_adapter.py`) - there is no OpenLane hardening
> run in this repo. Getting from here to a submittable GDS would still need
> a `tt/config.yaml` + OpenLane run against the official
> [tt-support-tools](https://github.com/TinyTapeout/tt-support-tools) flow.

## Why byte-serial?

tiny-gpu's native interfaces are wide and parallel: a 16-bit program memory
read port, one 8-bit read/write port *per thread*, plus a device control
register - far more signals than 24 pins can carry directly. The adapter
time-multiplexes all of it over one shared 8-bit byte lane in each direction,
framed by a small command protocol, and gives the wrapped GPU its own
internal program/data memory (loaded entirely over that link before the
kernel starts) instead of exposing tiny-gpu's external async memory ports at
all.

## Pinout

| TT pin | Direction | Usage |
|---|---|---|
| `ui_in[7:0]` | in | Command / payload byte from host |
| `uo_out[7:0]` | out | Response / status byte to host |
| `uio[0]` | out | `device_ready` - device can accept the next command/payload byte |
| `uio[1]` | in | `host_valid` - host is presenting a byte on `ui_in` this cycle |
| `uio[2]` | out | `device_valid` - device is presenting a response byte on `uo_out` |
| `uio[3]` | in | `host_ready` - host has consumed the response byte |
| `uio[7:4]` | - | Unused (driven low by the device; ignored on input) |
| `clk` | in | System clock |
| `rst_n` | in | Active-low reset |
| `ena` | in | Tied high by the TT harness when powered; unused by the design |

`uio_oe` is fixed: bits 0 and 2 are outputs (`device_ready`, `device_valid`),
all other bits are inputs.

## Protocol

Every transaction is a single command byte optionally followed by payload
bytes, using a standard valid/ready handshake: the host waits for
`device_ready`, drives `ui_in` + pulses `host_valid` for one clock, and
repeats for each payload byte. Response-bearing commands finish with the
device pulsing `device_valid` while holding the response on `uo_out` until
the host pulses `host_ready`.

| Opcode | Name | Payload (host → device) | Response | Effect |
|---|---|---|---|---|
| `0x01` | `LOAD_PROGRAM` | `addr`, `data_hi`, `data_lo` | - | `program_mem[addr] = {data_hi, data_lo}` (16-bit instruction) |
| `0x02` | `LOAD_DATA` | `addr`, `data` | - | `data_mem[addr] = data` |
| `0x03` | `SET_THREADS` | `count` | - | Writes the device control register (total thread count) |
| `0x04` | `START` | - | - | Launches the kernel (`start` held high internally until reset) |
| `0x05` | `READ_DATA` | `addr` | 1 byte | Returns `data_mem[addr]` |
| `0x06` | `READ_STATUS` | - | 1 byte | Returns `{7'b0, done}` |

Typical host sequence: `LOAD_PROGRAM` for every instruction → `LOAD_DATA` for
every input byte → `SET_THREADS` → `START` → poll `READ_STATUS` until
`done` = 1 → `READ_DATA` to collect results.

See `test/test_tt_adapter.py` for a complete worked example (a 4-element
matrix-addition kernel driven entirely through this protocol), and
`docs/tiny_tapeout.md`'s pinout table above for the exact handshake wiring.

## Configuration

- 1 core, 4 threads per block - larger thread counts are still supported
  (the single core just processes the resulting blocks one at a time, same
  as the full multi-core GPU would across its cores).
- `PROGRAM_MEM_ADDR_BITS` / `DATA_MEM_ADDR_BITS` = 8 (256 words / 256 bytes),
  matching the main design so every existing kernel test program fits
  unmodified.

## Future work

- Real OpenLane hardening run + `tt/config.yaml` for an actual shuttle
  submission.
- A faster (e.g. 2-byte-wide) transfer mode if `uio` budget allows shrinking
  the handshake to 2 pins instead of 4.
- Multi-core configurations once TT's pin budget (or a future ASIC target
  with more I/O) allows exposing more parallelism.
