"""
Optional live-streaming + trace-recording hook for GUI-enabled test runs
(`make gui_matadd`, `make gui_matmul`, `make gui_graphics`).

Entirely opt-in via environment variables, so plain `make test_*` runs are
completely unaffected (SimStreamer.enabled is False and every method is a
no-op):
  TINYGPU_GUI=1            enable streaming/recording at all
  TINYGPU_GUI_HOST/PORT    where sim/server.py's ingest socket is listening
                            (default 127.0.0.1:8765)
  TINYGPU_GUI_TRACE        path to also append a .jsonl trace file
  TINYGPU_GUI_SPEED        initial delay in seconds between cycles (float,
                            default 0 = as fast as possible)

sim/server.py accepts one line-delimited JSON object per message on the
ingest socket (`{"type": "snapshot", ...}` / `{"type": "hello", ...}` /
`{"type": "done"}`) and, symmetrically, sends control commands back down the
same socket (`{"type": "pause"|"play"|"step"|"speed", ...}`) which the
browser triggers via its own WebSocket connection to the server.
"""
import json
import os
import socket
from typing import Optional

from .snapshot import capture_snapshot


class SimStreamer:
    def __init__(self, kernel_name: str):
        self.kernel_name = kernel_name
        self.enabled = os.environ.get("TINYGPU_GUI") == "1"
        self.sock: Optional[socket.socket] = None
        self.trace_file = None
        self.paused = False
        self.step_once = False
        try:
            self.delay = float(os.environ.get("TINYGPU_GUI_SPEED", "0"))
        except ValueError:
            self.delay = 0.0
        self._recv_buf = b""

        if not self.enabled:
            return

        host = os.environ.get("TINYGPU_GUI_HOST", "127.0.0.1")
        port = int(os.environ.get("TINYGPU_GUI_PORT", "8765"))
        try:
            self.sock = socket.create_connection((host, port), timeout=2)
            self.sock.setblocking(False)
            self._send({"type": "hello", "kernel": self.kernel_name})
        except OSError:
            self.sock = None  # dashboard server not running - degrade to trace-only/no-op

        trace_path = os.environ.get("TINYGPU_GUI_TRACE")
        if trace_path:
            self.trace_file = open(trace_path, "w")

    def _send(self, obj) -> None:
        if not self.sock:
            return
        try:
            self.sock.sendall((json.dumps(obj) + "\n").encode())
        except OSError:
            self.sock = None

    def _poll_commands(self) -> None:
        if not self.sock:
            return
        try:
            data = self.sock.recv(65536)
            if not data:
                self.sock = None
                return
            self._recv_buf += data
        except BlockingIOError:
            pass
        except OSError:
            self.sock = None
            return

        while b"\n" in self._recv_buf:
            line, self._recv_buf = self._recv_buf.split(b"\n", 1)
            if not line.strip():
                continue
            try:
                cmd = json.loads(line)
            except json.JSONDecodeError:
                continue
            self._handle_command(cmd)

    def _handle_command(self, cmd) -> None:
        ctype = cmd.get("type")
        if ctype == "pause":
            self.paused = True
        elif ctype == "play":
            self.paused = False
        elif ctype == "step":
            self.paused = True
            self.step_once = True
        elif ctype == "speed":
            try:
                self.delay = float(cmd.get("value", 0.0))
            except (TypeError, ValueError):
                pass

    async def tick(self, dut, cycle_id: int, data_memory=None, program_memory=None) -> None:
        """Call once per cycle (ideally right after `ReadOnly()`) from a test's
        main loop. No-ops entirely unless TINYGPU_GUI=1."""
        if not self.enabled:
            return
        from cocotb.triggers import Timer  # local import: keep this module importable outside cocotb sims

        snapshot = capture_snapshot(dut, cycle_id, data_memory=data_memory, program_memory=program_memory)
        snapshot["kernel"] = self.kernel_name
        self._send({"type": "snapshot", "data": snapshot})
        if self.trace_file:
            self.trace_file.write(json.dumps(snapshot) + "\n")

        self._poll_commands()
        while self.paused and not self.step_once:
            await Timer(20, units="ms")
            self._poll_commands()
        self.step_once = False

        if self.delay > 0:
            await Timer(max(int(self.delay * 1_000_000), 1), units="ns")

    def close(self) -> None:
        if self.sock:
            self._send({"type": "done"})
            try:
                self.sock.close()
            except OSError:
                pass
            self.sock = None
        if self.trace_file:
            self.trace_file.close()
            self.trace_file = None
