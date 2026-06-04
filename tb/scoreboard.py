def read_reg(dut, thread_idx, reg_idx):

    return int(
        dut.g_core[thread_idx]
           .register_instance
           .register_file[reg_idx]
           .value
    )


def read_nzp(dut, thread_idx):

    return int(
        dut.g_core[thread_idx]
           .pc_instance
           .nzp
           .value
    )