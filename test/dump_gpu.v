module dump();
    initial begin
        $dumpfile ("gpu.vcd");
        $dumpvars (0, gpu);
        #1;
    end
endmodule
