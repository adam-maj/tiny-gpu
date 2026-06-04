from pathlib import Path
from cocotb_test.simulator import run
import sys

ROOT = Path(__file__).resolve().parent.parent
TB_DIR = ROOT / "tb"

sys.path.insert(0, str(TB_DIR))

def test_alu():

    run(
        simulator="verilator",

        verilog_sources=[
            str(ROOT / "rtl/common/gpu_pkg.sv"),
            str(ROOT / "rtl/core/alu.sv"),
        ],

        includes=[
            str(ROOT / "rtl/common"),
        ],

        toplevel="alu",

        module="tb.test_alu",

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