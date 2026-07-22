#!/usr/bin/env python3
"""
Live web dashboard server for tiny-gpu.

Two modes:

  Live mode (default):
    python sim/server.py [--http-port 8080] [--ingest-port 8765]

    Serves the dashboard frontend (sim/web/) over HTTP/WebSocket, and opens
    a plain-TCP "ingest" socket that a cocotb test process connects to (see
    test/helpers/streaming.py's SimStreamer, enabled via TINYGPU_GUI=1).
    Every line-delimited JSON snapshot the simulator sends is broadcast to
    all connected browser WebSocket clients; pause/play/step/speed commands
    sent *from* the browser are relayed back down the same ingest socket so
    the simulation can react to them cycle-by-cycle.

  Live + auto-run (used by `make gui_*`):
    python sim/server.py --run test.test_matadd --sim-vvp build/sim.vvp

    Same as live mode, but after the ingest socket is up the server also
    launches `vvp` with TINYGPU_GUI=1 so a browser pointed at the printed
    URL sees the kernel execute live.

  Replay mode:
    python sim/server.py --replay build/traces/matadd.jsonl [--http-port 8080]

    Loads a previously recorded .jsonl trace (one JSON object per cycle,
    written by SimStreamer when TINYGPU_GUI_TRACE is set) and serves it to
    the dashboard with the same pause/play/step/speed controls, plus
    scrubbing to an arbitrary cycle - no simulator process required.

See docs/gui.md for the on-the-wire message formats.
"""
import argparse
import asyncio
import json
import os
import shutil
import signal
import subprocess
import sys
from typing import Any, Dict, Optional, Set

from aiohttp import web, WSMsgType

WEB_DIR = os.path.join(os.path.dirname(__file__), "web")
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


class LiveHub:
    """Bridges the single cocotb ingest connection <-> N browser WebSockets."""

    mode = "live"

    def __init__(self) -> None:
        self.ws_clients: Set[web.WebSocketResponse] = set()
        self.ingest_writer: Optional[asyncio.StreamWriter] = None
        self.latest_snapshot: Optional[Dict[str, Any]] = None
        self.kernel_name: Optional[str] = None
        self.sim_done = False
        self.sim_proc: Optional[subprocess.Popen] = None
        self.run_module: Optional[str] = None
        self.sim_vvp: Optional[str] = None
        self.ingest_port: Optional[int] = None
        self._restart_lock: Optional[asyncio.Lock] = None

    def _get_restart_lock(self) -> asyncio.Lock:
        if self._restart_lock is None:
            self._restart_lock = asyncio.Lock()
        return self._restart_lock

    @property
    def can_restart(self) -> bool:
        return bool(self.run_module and self.sim_vvp and self.ingest_port is not None)

    async def broadcast(self, message: Dict[str, Any]) -> None:
        dead = []
        for ws in self.ws_clients:
            try:
                await ws.send_json(message)
            except (ConnectionResetError, RuntimeError):
                dead.append(ws)
        for ws in dead:
            self.ws_clients.discard(ws)

    async def handle_ingest_message(self, msg: Dict[str, Any]) -> None:
        mtype = msg.get("type")
        if mtype == "hello":
            self.kernel_name = msg.get("kernel")
            self.sim_done = False
            await self.broadcast({"type": "hello", "kernel": self.kernel_name})
        elif mtype == "snapshot":
            self.latest_snapshot = msg.get("data")
            await self.broadcast({"type": "snapshot", "data": self.latest_snapshot})
        elif mtype == "done":
            self.sim_done = True
            await self.broadcast({"type": "done"})

    async def stop_sim(self) -> None:
        """Kill any running vvp process and drop the ingest link."""
        writer = self.ingest_writer
        self.ingest_writer = None
        if writer is not None:
            try:
                writer.close()
                await writer.wait_closed()
            except Exception:
                pass

        proc = self.sim_proc
        self.sim_proc = None
        if proc is not None and proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except (ProcessLookupError, PermissionError):
                try:
                    proc.terminate()
                except ProcessLookupError:
                    pass

            def _wait() -> None:
                try:
                    proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    try:
                        os.killpg(proc.pid, signal.SIGKILL)
                    except (ProcessLookupError, PermissionError):
                        try:
                            proc.kill()
                        except ProcessLookupError:
                            pass
                    proc.wait(timeout=2)

            await asyncio.get_event_loop().run_in_executor(None, _wait)

        self.latest_snapshot = None
        self.sim_done = False

    async def handle_command(self, cmd: Dict[str, Any]) -> None:
        """Browser commands: restart relaunches vvp; everything else is relayed to the sim."""
        if cmd.get("type") == "restart":
            if not self.can_restart:
                return
            async with self._get_restart_lock():
                await self.broadcast({"type": "restarting"})
                await self.stop_sim()
                # Optional: let the browser's current speed slider become the next run's pace
                if "value" in cmd:
                    try:
                        os.environ["TINYGPU_GUI_SPEED"] = str(max(float(cmd["value"]), 0.0))
                    except (TypeError, ValueError):
                        pass
                await launch_sim_for_hub(self)
            return

        if not self.ingest_writer:
            return
        try:
            self.ingest_writer.write((json.dumps(cmd) + "\n").encode())
            await self.ingest_writer.drain()
        except (ConnectionResetError, BrokenPipeError):
            self.ingest_writer = None


class ReplayHub:
    """Serves a pre-recorded .jsonl trace with local pause/play/step/scrub/speed."""

    mode = "replay"

    def __init__(self, trace_path: str) -> None:
        self.ws_clients: Set[web.WebSocketResponse] = set()
        self.trace = []
        with open(trace_path) as f:
            for line in f:
                line = line.strip()
                if line:
                    self.trace.append(json.loads(line))
        self.kernel_name = self.trace[0].get("kernel") if self.trace else None
        self.position = 0
        self.playing = False
        self.delay = 0.08  # seconds between cycles while playing

    @property
    def can_restart(self) -> bool:
        return bool(self.trace)

    async def broadcast(self, message: Dict[str, Any]) -> None:
        dead = []
        for ws in self.ws_clients:
            try:
                await ws.send_json(message)
            except (ConnectionResetError, RuntimeError):
                dead.append(ws)
        for ws in dead:
            self.ws_clients.discard(ws)

    async def _broadcast_current(self) -> None:
        if not self.trace:
            return
        await self.broadcast({
            "type": "snapshot",
            "data": self.trace[self.position],
            "position": self.position,
            "length": len(self.trace),
        })

    async def playback_loop(self) -> None:
        while True:
            if self.playing and self.trace and self.position < len(self.trace) - 1:
                self.position += 1
                await self._broadcast_current()
                await asyncio.sleep(self.delay)
            else:
                if self.playing and self.position >= len(self.trace) - 1:
                    self.playing = False
                    await self.broadcast({"type": "done"})
                await asyncio.sleep(0.05)

    async def handle_command(self, cmd: Dict[str, Any]) -> None:
        ctype = cmd.get("type")
        if ctype == "pause":
            self.playing = False
        elif ctype == "play":
            self.playing = True
        elif ctype == "restart":
            if not self.trace:
                return
            await self.broadcast({"type": "restarting"})
            self.position = 0
            self.playing = True
            if "value" in cmd:
                try:
                    self.delay = max(float(cmd["value"]), 0.0)
                except (TypeError, ValueError):
                    pass
            await self._broadcast_current()
        elif ctype == "step":
            self.playing = False
            if self.trace and self.position < len(self.trace) - 1:
                self.position += 1
            await self._broadcast_current()
        elif ctype == "back":
            self.playing = False
            if self.position > 0:
                self.position -= 1
            await self._broadcast_current()
        elif ctype == "speed":
            try:
                self.delay = max(float(cmd.get("value", 0.08)), 0.0)
            except (TypeError, ValueError):
                pass
        elif ctype == "scrub":
            try:
                pos = int(cmd.get("value", 0))
            except (TypeError, ValueError):
                return
            self.position = max(0, min(pos, len(self.trace) - 1)) if self.trace else 0
            await self._broadcast_current()

async def index_handler(request: web.Request) -> web.Response:
    return web.FileResponse(os.path.join(WEB_DIR, "index.html"))


async def ws_handler(request: web.Request) -> web.WebSocketResponse:
    hub = request.app["hub"]
    ws = web.WebSocketResponse(heartbeat=20)
    await ws.prepare(request)
    hub.ws_clients.add(ws)
    try:
        await ws.send_json({
            "type": "meta",
            "mode": hub.mode,
            "kernel": hub.kernel_name,
            "length": len(hub.trace) if hub.mode == "replay" else None,
            "can_restart": hub.can_restart,
        })
        if hub.mode == "live" and hub.latest_snapshot is not None:
            await ws.send_json({"type": "snapshot", "data": hub.latest_snapshot})
        elif hub.mode == "replay" and hub.trace:
            await hub._broadcast_current()

        async for msg in ws:
            if msg.type == WSMsgType.TEXT:
                try:
                    cmd = json.loads(msg.data)
                except json.JSONDecodeError:
                    continue
                await hub.handle_command(cmd)
            elif msg.type in (WSMsgType.CLOSE, WSMsgType.ERROR):
                break
    finally:
        hub.ws_clients.discard(ws)
    return ws


async def start_ingest_server(app: web.Application, host: str, port: int) -> None:
    hub: LiveHub = app["hub"]

    async def handle_conn(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        hub.ingest_writer = writer
        try:
            while True:
                line = await reader.readline()
                if not line:
                    break
                line = line.strip()
                if not line:
                    continue
                try:
                    msg = json.loads(line)
                except json.JSONDecodeError:
                    continue
                await hub.handle_ingest_message(msg)
        except (ConnectionResetError, asyncio.IncompleteReadError):
            pass
        finally:
            if hub.ingest_writer is writer:
                hub.ingest_writer = None

    server = await asyncio.start_server(handle_conn, host, port, limit=1 << 20)
    app["ingest_server"] = server
    print(f"[sim/server.py] Ingest socket listening on {host}:{port} (for cocotb SimStreamer)")


async def on_cleanup(app: web.Application) -> None:
    hub = app.get("hub")
    if isinstance(hub, LiveHub):
        await hub.stop_sim()
    server = app.get("ingest_server")
    if server:
        server.close()
        await server.wait_closed()


async def launch_sim_for_hub(hub: LiveHub, initial_delay: float = 0.0) -> None:
    """Spawn vvp+cocotb with GUI streaming enabled for a LiveHub configured with --run."""
    if initial_delay > 0:
        await asyncio.sleep(initial_delay)

    module = hub.run_module
    sim_vvp = hub.sim_vvp
    ingest_port = hub.ingest_port
    if not module or not sim_vvp or ingest_port is None:
        print("[sim/server.py] error: cannot launch sim — missing --run configuration", file=sys.stderr)
        return

    cocotb_config = shutil.which("cocotb-config") or os.path.join(REPO_ROOT, ".venv", "bin", "cocotb-config")
    vvp = shutil.which("vvp")
    if not vvp:
        print("[sim/server.py] error: `vvp` not found on PATH (source scripts/env.sh first)", file=sys.stderr)
        return
    if not os.path.exists(sim_vvp):
        print(f"[sim/server.py] error: sim vvp not found: {sim_vvp}", file=sys.stderr)
        return

    lib_dir = subprocess.check_output([cocotb_config, "--lib-dir"], text=True).strip()
    env = os.environ.copy()
    env["TINYGPU_GUI"] = "1"
    env["TINYGPU_GUI_HOST"] = "127.0.0.1"
    env["TINYGPU_GUI_PORT"] = str(ingest_port)
    env["TINYGPU_GUI_SPEED"] = env.get("TINYGPU_GUI_SPEED", "0.02")
    env["MODULE"] = module

    # Optional: also dump a replayable trace next to the sim binary
    trace_dir = os.path.join(REPO_ROOT, "build", "traces")
    os.makedirs(trace_dir, exist_ok=True)
    kernel = module.rsplit(".", 1)[-1].replace("test_", "")
    env.setdefault("TINYGPU_GUI_TRACE", os.path.join(trace_dir, f"{kernel}.jsonl"))

    cmd = ["vvp", "-M", lib_dir, "-m", "libcocotbvpi_icarus", sim_vvp]
    print(f"[sim/server.py] Launching simulation: MODULE={module} {' '.join(cmd)}")
    print(f"[sim/server.py] Trace will also be saved to {env['TINYGPU_GUI_TRACE']}")
    proc = subprocess.Popen(
        cmd,
        cwd=REPO_ROOT,
        env=env,
        start_new_session=True,
    )
    hub.sim_proc = proc


def build_app(
    hub,
    ingest_host: Optional[str],
    ingest_port: Optional[int],
    run_module: Optional[str] = None,
    sim_vvp: Optional[str] = None,
) -> web.Application:
    app = web.Application()
    app["hub"] = hub
    if isinstance(hub, LiveHub):
        hub.run_module = run_module
        hub.sim_vvp = sim_vvp
        hub.ingest_port = ingest_port
        hub.sim_proc = None
    app.router.add_get("/", index_handler)
    app.router.add_get("/ws", ws_handler)
    static_dir = os.path.join(WEB_DIR, "static")
    app.router.add_static("/static/", path=static_dir, name="static")

    if hub.mode == "live":
        async def _startup(app: web.Application) -> None:
            await start_ingest_server(app, ingest_host, ingest_port)
            if run_module and sim_vvp:
                # Small delay so the ingest listener is fully bound before vvp connects
                asyncio.create_task(launch_sim_for_hub(hub, initial_delay=0.3))
        app.on_startup.append(_startup)
        app.on_cleanup.append(on_cleanup)
    else:
        async def _startup(app: web.Application) -> None:
            app["replay_task"] = asyncio.ensure_future(hub.playback_loop())
        app.on_startup.append(_startup)

    return app


def main() -> None:
    parser = argparse.ArgumentParser(description="tiny-gpu live/replay web dashboard")
    parser.add_argument("--http-port", type=int, default=int(os.environ.get("TINYGPU_GUI_HTTP_PORT", 8080)))
    parser.add_argument("--ingest-host", default="127.0.0.1")
    parser.add_argument("--ingest-port", type=int, default=int(os.environ.get("TINYGPU_GUI_PORT", 8765)))
    parser.add_argument("--replay", metavar="TRACE.jsonl", default=None,
                         help="Serve a recorded trace instead of listening for a live simulator")
    parser.add_argument("--run", metavar="MODULE", default=None,
                         help="Auto-launch a cocotb MODULE (e.g. test.test_matadd) once the ingest socket is up")
    parser.add_argument("--sim-vvp", default=os.path.join(REPO_ROOT, "build", "sim.vvp"),
                         help="Path to the compiled Icarus VVP binary used with --run")
    args = parser.parse_args()

    if args.replay and args.run:
        print("error: --replay and --run are mutually exclusive", file=sys.stderr)
        sys.exit(1)

    if args.replay:
        if not os.path.exists(args.replay):
            print(f"error: trace file not found: {args.replay}", file=sys.stderr)
            sys.exit(1)
        hub = ReplayHub(args.replay)
        print(f"[sim/server.py] Replaying {args.replay} ({len(hub.trace)} cycles)")
        app = build_app(hub, None, None)
    else:
        hub = LiveHub()
        app = build_app(hub, args.ingest_host, args.ingest_port, args.run, args.sim_vvp)

    print(f"[sim/server.py] Dashboard: http://localhost:{args.http_port}")
    if args.run:
        print(f"[sim/server.py] Will auto-run {args.run} against {args.sim_vvp}")
    web.run_app(app, host="0.0.0.0", port=args.http_port, print=None)


if __name__ == "__main__":
    main()
