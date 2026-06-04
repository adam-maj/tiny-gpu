from pathlib import Path
from cocotb_test.simulator import run

ROOT = Path(__file__).resolve().parent.parent
TB_DIR = ROOT / "tb"


def test_core_programs():

    run(
        simulator="verilator",

        verilog_sources=[
            str(ROOT / "rtl/common/gpu_pkg.sv"),

            str(ROOT / "rtl/core/alu.sv"),
            str(ROOT / "rtl/core/decode.sv"),
            str(ROOT / "rtl/core/fetch.sv"),
            str(ROOT / "rtl/core/lsu.sv"),
            str(ROOT / "rtl/core/pc.sv"),
            str(ROOT / "rtl/core/register_file.sv"),

            str(ROOT / "rtl/dispatch/scheduler.sv"),

            str(ROOT / "rtl/core/core.sv"),
        ],

        includes=[
            str(ROOT / "rtl/common"),
        ],

        toplevel="core",

        module="tb.test_core_programs",

        python_search=[
            str(TB_DIR),
        ],

        extra_args=[
            "--timing",
            "-Wno-EOFNEWLINE",
            "-Wno-IMPORTSTAR",
            "-Wno-UNUSEDPARAM",
        ],

        waves=True,
    )