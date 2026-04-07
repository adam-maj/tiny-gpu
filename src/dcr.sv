`default_nettype none
`timescale 1ns/1ns

// DEVICE CONTROL REGISTER
// > Used to configure high-level GPU launch settings.
// > In this minimal example, the DCR only stores one thing: the total number of threads
//   that should be launched for the next kernel.
// > Beginner mental model:
//   software/testbench writes one 8-bit value here, and the dispatcher later reads it.
// 新手导读：
// 1. 这是一个最简单的“配置寄存器”模块，本质上就是在时钟边沿把外部写进来的值存起来。
// 2. Verilog 里 `input`/`output` 描述端口方向，`[7:0]` 表示这个端口宽度是 8 bit。
// 3. `assign thread_count = ...` 表示把内部寄存器的某几位直接连到输出端口。
// 4. 这里没有复杂协议，只有一个写使能 `device_control_write_enable`，为 1 时就在该拍写入数据。
module dcr (
    input wire clk,
    input wire reset,

    // Simple write interface from the outside world / testbench.
    input wire device_control_write_enable,
    input wire [7:0] device_control_data,

    // Current configured total thread count for the kernel launch.
    output wire [7:0] thread_count,
);
    // Internal storage register for the device control data.
    // `reg [7:0]` 表示定义一个 8 bit 的寄存器变量，用来跨时钟保存状态。
    reg [7:0] device_conrol_register;

    // In this design, the low 8 bits directly represent the kernel's total thread count.
    // 这行没有时钟，属于组合连线：输出 thread_count 永远等于内部寄存器当前值。
    assign thread_count = device_conrol_register[7:0];

    always @(posedge clk) begin
        if (reset) begin
            // Reset clears the launch configuration.
            device_conrol_register <= 8'b0;
        end else begin
            if (device_control_write_enable) begin 
                // Latch the new launch configuration when write_enable is high.
                // 非阻塞赋值 `<=` 表示在这个上升沿把输入数据写进内部寄存器。
                device_conrol_register <= device_control_data;
            end
        end
    end
endmodule
