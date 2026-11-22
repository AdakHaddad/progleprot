/*
 * Simple HALT test - just a few instructions then HALT
 */
module tb_halt_test;

    reg clk = 0;
    reg rst_n = 0;
    reg [7:0] ui_in = 8'h00;
    reg [7:0] uio_in = 8'hFF;
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    // Debug register interface
    reg [3:0] dbg_reg_idx = 4'd0;
    wire [15:0] dbg_reg_data;

    emu_top #(
        .NUM_PINS(8),
        .PROG_DEPTH(2048),
        .PROG_W(16),
        .ADDR_W(16)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .pin_in(ui_in),
        .pin_out(uo_out),
        .pin_oe(uio_oe[7:0]),
        .spi_sck(uio_in[0]),
        .spi_mosi(uio_in[1]),
        .spi_miso(uio_out[0]),
        .spi_cs_n(uio_in[2]),
        .cpu_running(uio_out[1]),
        .cpu_error(uio_out[2]),
        .dbg_reg_idx(dbg_reg_idx),
        .dbg_reg_data(dbg_reg_data)
    );

    always #10 clk = ~clk;

    task wait_clk(input integer n);
        integer j;
        begin for (j = 0; j < n; j = j + 1) @(negedge clk); end
    endtask

    function [63:0] make_spi_cmd;
        input [31:0] data;
        input [15:0] addr;
        input [7:0]  cmd;
        begin
            make_spi_cmd = {data, addr, cmd, 8'h00};
        end
    endfunction

    task spi_write(input [15:0] addr, input [31:0] data);
        integer b;
        reg [63:0] cmd;
        begin
            cmd = make_spi_cmd(data, addr, 8'h01);
            uio_in[2] = 0;
            wait_clk(2);
            for (b = 63; b >= 0; b = b - 1) begin
                uio_in[1] = cmd[b];
                uio_in[0] = 0; wait_clk(2);
                uio_in[0] = 1; wait_clk(2);
            end
            uio_in[2] = 1;
            wait_clk(4);
        end
    endtask

    task spi_run(input [15:0] length);
        integer b;
        reg [63:0] cmd;
        begin
            cmd = make_spi_cmd(32'h0, length, 8'h03);
            uio_in[2] = 0;
            wait_clk(2);
            for (b = 63; b >= 0; b = b - 1) begin
                uio_in[1] = cmd[b];
                uio_in[0] = 0; wait_clk(2);
                uio_in[0] = 1; wait_clk(2);
            end
            uio_in[2] = 1;
            wait_clk(10);
        end
    endtask

    // Simple program: ADDI x1, 5; ADDI x2, 10; ADD x3, x1, x2; HALT
    // ADDI x1, 5:  0x8105
    // ADDI x2, 10: 0x820A
    // ADD x3, x1, x2: 0x0312
    // HALT: 0xFFFF

    initial begin
        rst_n = 0;
        wait_clk(4);
        rst_n = 1;
        wait_clk(4);

        $display("=== HALT Test ===");

        // Load program
        spi_write(16'h0000, 32'h820A8105);  // ADDI x1,5 ; ADDI x2,10
        spi_write(16'h0002, 32'hFFFF0312);  // ADD x3,x1,x2 ; HALT

        $display("Program loaded. Starting CPU...");
        spi_run(16'd8);  // 4 instructions * 2 bytes

        // Wait for CPU to complete
        wait_clk(1000);

        $display("=== CPU Registers ===");
        dbg_reg_idx = 4'd0; wait_clk(1); $display("R0: %h", dbg_reg_data);
        dbg_reg_idx = 4'd1; wait_clk(1); $display("R1: %h (should be 5)", dbg_reg_data);
        dbg_reg_idx = 4'd2; wait_clk(1); $display("R2: %h (should be 10)", dbg_reg_data);
        dbg_reg_idx = 4'd3; wait_clk(1); $display("R3: %h (should be 15)", dbg_reg_data);
        $display("PC: %h", dut.u_cpu.pc_debug);
        $display("cpu_running (internal): %b", dut.u_cpu.cpu_running);
        $display("cpu_done: %b", dut.cpu_done);
        
        $display("=== Test Complete ===");
        $finish;
    end

    // Monitor CPU running state
    always @(posedge clk) begin
        if (dut.u_cpu.cpu_running != cpu_running_d) begin
            $display("t=%0t CPU running: %b -> %b (PC=%h, pipe_st=%d)", $time, cpu_running_d, dut.u_cpu.cpu_running, dut.u_cpu.pc_debug, dut.u_cpu.pipe_st);
            cpu_running_d = dut.u_cpu.cpu_running;
        end
        if (dut.cpu_done != cpu_done_d) begin
            $display("t=%0t CPU done: %b -> %b", $time, cpu_done_d, dut.cpu_done);
            cpu_done_d = dut.cpu_done;
        end
        if (dut.u_cpu.wb_is_halt) begin
            $display("t=%0t WB HALT! PC=%h", $time, dut.u_cpu.pc_debug);
        end
    end
    reg cpu_running_d = 0;
    reg cpu_done_d = 0;

    // Timeout
    initial begin #50000; $display("TIMEOUT"); $finish; end

endmodule
