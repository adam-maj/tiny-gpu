from pathlib import Path
from cocotb_test.simulator import run

ROOT = Path(__file__).resolve().parent.parent
TB_DIR = ROOT / "tb"


def test_scheduler():

    run(
        simulator="verilator",

        verilog_sources=[
            str(ROOT / "rtl/common/gpu_pkg.sv"),
            str(ROOT / "rtl/dispatch/scheduler.sv"),
        ],

        includes=[
            str(ROOT / "rtl/common"),
        ],

        toplevel="scheduler",

        module="tb.test_scheduler",

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