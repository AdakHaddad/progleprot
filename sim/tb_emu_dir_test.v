/*
 * DIR instruction test - verify pin direction is set correctly
 */
module tb_emu_dir_test;

    reg clk = 0;
    reg rst_n = 0;
    reg [7:0] ui_in = 8'h00;
    reg [7:0] uio_in = 8'hFF;
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

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
        .cpu_error(uio_out[2])
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

    // Simple program: ADDI x1=pin0, ADDI x2=1, DIR x1,x2, HALT
    localparam [15:0] INS_ADDI_x1_00  = 16'h8100;  // R1 = pin 0
    localparam [15:0] INS_ADDI_x2_01  = 16'h8201;  // R2 = 1 (output)
    localparam [15:0] INS_DIR_x1_x2   = 16'hF112;  // DIR R1, R2 (pin0, output)
    localparam [15:0] INS_HALT        = 16'hFFFF;

    initial begin
        rst_n = 0;
        wait_clk(4);
        rst_n = 1;
        wait_clk(4);

        $display("=== DIR Instruction Test ===");

        // Load program
        spi_write(16'h0000, {INS_ADDI_x2_01, INS_ADDI_x1_00});   // R1=pin0, R2=1
        spi_write(16'h0002, {INS_HALT, INS_DIR_x1_x2});           // DIR, HALT

        $display("Program loaded. Starting CPU...");
        spi_run(16'd8);  // 4 instructions

        wait_clk(1000);

        $display("=== CPU Registers ===");
        $display("R0: %h", dut.u_cpu.reg_debug[0]);
        $display("R1: %h (pin)", dut.u_cpu.reg_debug[1]);
        $display("R2: %h (dir)", dut.u_cpu.reg_debug[2]);
        $display("PC: %h", dut.u_cpu.pc_debug);
        $display("Pin 0 out: %b, OE: %b", uo_out[0], uio_oe[0]);
        $display("Pin Matrix DIR reg: %b", dut.u_pin_matrix.pin_dir);

        $display("=== Test Complete ===");
        $finish;
    end

    // Monitor pin_matrix internals
    always @(posedge clk) begin
        if (dut.u_cpu.cpu_running) begin
            if (dut.u_pin_matrix.wr_en) begin
                $display("t=%0t PIN_MATRIX WR: addr=%h data=%h", $time, dut.u_pin_matrix.wr_addr, dut.u_pin_matrix.wr_data);
            end
        end
    end

    initial begin #50000; $display("TIMEOUT"); $finish; end

endmodule
