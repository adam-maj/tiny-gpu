from pathlib import Path
from cocotb_test.simulator import run

ROOT = Path(__file__).resolve().parent.parent
TB_DIR = ROOT / "tb"

def test_lsu():

    run(
        simulator="verilator",

        verilog_sources=[
            str(ROOT / "rtl/common/gpu_pkg.sv"),
            str(ROOT / "rtl/core/lsu.sv"),
        ],

        includes=[
            str(ROOT / "rtl/common"),
        ],

        toplevel="lsu",

        module="tb.test_lsu",

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