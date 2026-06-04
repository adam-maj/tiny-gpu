from pathlib import Path
from cocotb_test.simulator import run

ROOT = Path(__file__).resolve().parent.parent


def test_gpu_top():
    run(
        simulator="verilator",

        verilog_sources=[
            str(ROOT / "rtl/common/gpu_pkg.sv"),

            str(ROOT / "rtl/core/alu.sv"),
            str(ROOT / "rtl/core/controller.sv"),
            str(ROOT / "rtl/core/core.sv"),
            str(ROOT / "rtl/core/decode.sv"),
            str(ROOT / "rtl/core/fetch.sv"),
            str(ROOT / "rtl/core/lsu.sv"),
            str(ROOT / "rtl/core/pc.sv"),
            str(ROOT / "rtl/core/register_file.sv"),

            str(ROOT / "rtl/control/dcr.sv"),

            str(ROOT / "rtl/dispatch/block_dispatch.sv"),
            str(ROOT / "rtl/dispatch/scheduler.sv"),

            str(ROOT / "rtl/scheduler/warp_context.sv"),
            str(ROOT / "rtl/scheduler/warp_scheduler.sv"),
            str(ROOT / "rtl/scheduler/warp_table.sv"),

            str(ROOT / "rtl/top/gpu_top.sv"),
        ],  # <-- missing comma

        includes=[
            str(ROOT / "rtl/common"),
        ],

        toplevel="gpu_top",
        module="tb.test_gpu_top",

        python_search=[
            str(ROOT / "tb"),
        ],

        extra_args=[
            "--timing",
            "-Wno-EOFNEWLINE",
            "-Wno-IMPORTSTAR",
            "-Wno-UNUSEDPARAM",
        ],

        waves=True,
    )