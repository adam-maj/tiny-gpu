import os


_DEBUGPY_INITIALIZED = False


def _env_enabled(name: str) -> bool:
    value = os.getenv(name, "").strip().lower()
    return value in {"1", "true", "yes", "on"}


def maybe_enable_debugpy() -> None:
    global _DEBUGPY_INITIALIZED

    if not _env_enabled("COCOTB_DEBUGPY"):
        return

    if _DEBUGPY_INITIALIZED:
        return

    try:
        import debugpy
    except ImportError as exc:
        raise RuntimeError(
            "COCOTB_DEBUGPY=1 but debugpy is not installed in the cocotb Python environment"
        ) from exc

    host = os.getenv("COCOTB_DEBUGPY_HOST", "127.0.0.1")
    port = int(os.getenv("COCOTB_DEBUGPY_PORT", "5678"))
    wait_for_attach = _env_enabled("COCOTB_DEBUGPY_WAIT")

    debugpy.listen((host, port))
    _DEBUGPY_INITIALIZED = True

    print(f"[cocotb-debug] Listening on {host}:{port}", flush=True)

    if wait_for_attach:
        print(
            f"[cocotb-debug] Waiting for debugger attach on {host}:{port}", flush=True
        )
        debugpy.wait_for_client()
        print(f"[cocotb-debug] Debugger attached on {host}:{port}", flush=True)
