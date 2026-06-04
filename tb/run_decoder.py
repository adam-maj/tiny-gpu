from pathlib import Path
from cocotb_test.simulator import run

ROOT = Path(__file__).resolve().parent.parent
TB_DIR = ROOT / "tb"


def test_decoder():

    run(
        simulator="verilator",

        verilog_sources=[
            str(ROOT / "rtl/common/gpu_pkg.sv"),
            str(ROOT / "rtl/core/decode.sv"),
        ],

        includes=[
            str(ROOT / "rtl/common"),
        ],

        toplevel="decoder",

        module="tb.test_decoder",

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