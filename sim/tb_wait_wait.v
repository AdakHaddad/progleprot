/*
 * Test back-to-back WAIT instructions
 */
module tb_wait_wait;

    reg clk = 0;
    reg rst_n = 0;
    reg [7:0] ui_in = 8'h00;
    reg [7:0] uio_in = 8'hFF;
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

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

    // WAIT timer 0, 50 cycles: 0xF232 (funct=2, rs1=0, rs2=2)
    // But rs2 should be register with value 50. Let's use x8=50
    // ADDI x8, 50: 0x8832
    // WAIT x11, x8: 0xF2B8 (timer 0=x11, cycles=x8)
    // HALT: 0xFFFF

    localparam [15:0] INS_ADDI_x11_00 = 16'h8B00;  // timer 0
    localparam [15:0] INS_ADDI_x8_32  = 16'h8832;  // wait 50
    localparam [15:0] INS_WAIT_1      = 16'hF2B8;  // WAIT timer 0, cycles=x8
    localparam [15:0] INS_WAIT_2      = 16'hF2B8;  // WAIT timer 0, cycles=x8
    localparam [15:0] INS_HALT        = 16'hFFFF;

    initial begin
        rst_n = 0;
        wait_clk(4);
        rst_n = 1;
        wait_clk(4);

        $display("=== Back-to-back WAIT Test ===");

        spi_write(16'h0000, {INS_ADDI_x11_00, INS_ADDI_x8_32});
        spi_write(16'h0002, {INS_WAIT_1,      INS_WAIT_2});
        spi_write(16'h0004, {INS_HALT,        16'h0000});

        $display("Program loaded. Starting CPU...");
        spi_run(16'd12);  // 6 instructions * 2 bytes

        wait_clk(10000);

        $display("=== CPU Registers ===");
        dbg_reg_idx = 4'd8; wait_clk(1); $display("R8 (wait): %h", dbg_reg_data);
        dbg_reg_idx = 4'd11; wait_clk(1); $display("R11 (timer): %h", dbg_reg_data);
        $display("PC: %h", dut.u_cpu.pc_debug);
        $display("cpu_running: %b", dut.u_cpu.cpu_running);
        $display("cpu_done: %b", dut.cpu_done);
        
        $display("=== Test Complete ===");
        $finish;
    end

    always @(posedge clk) begin
        if (dut.u_cpu.cpu_running != cpu_running_d) begin
            $display("t=%0t CPU running: %b -> %b (PC=%h, pipe_st=%d)", $time, cpu_running_d, dut.u_cpu.cpu_running, dut.u_cpu.pc_debug, dut.u_cpu.pipe_st);
            cpu_running_d = dut.u_cpu.cpu_running;
        end
        if (dut.cpu_done != cpu_done_d) begin
            $display("t=%0t CPU done: %b -> %b", $time, cpu_done_d, dut.cpu_done);
            cpu_done_d = dut.cpu_done;
        end
    end
    reg cpu_running_d = 0;
    reg cpu_done_d = 0;

    initial begin #200000; $display("TIMEOUT"); $finish; end

endmodule
