/*
 * I²C Master Testbench - CPU Architecture with IHP SRAM
 * Tests I²C Master firmware using CPU with NCO timer for clock generation
 */
module tb_emu_i2c_master_ihp;

    reg clk = 0;
    reg rst_n = 0;
    reg [7:0] ui_in = 8'h03;
    reg [7:0] uio_in = 8'hFF;
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    reg [3:0] dbg_reg_idx = 4'd0;
    wire [15:0] dbg_reg_data;

    emu_top_ihp #(
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

    // I²C firmware instructions
    localparam [15:0] INS_ADDI_x1_B8   = 16'h81B8;
    localparam [15:0] INS_ADDI_x9_1E   = 16'h891E;
    localparam [15:0] INS_ADDI_x10_05  = 16'h8A05;
    localparam [15:0] INS_ADD_x9_x9_x10 = 16'h099A;
    localparam [15:0] INS_ADDI_x11_00  = 16'h8B00;
    localparam [15:0] INS_ADDI_x12_03  = 16'h8C03;
    localparam [15:0] INS_TCFG_x11_x12 = 16'hF5B3;
    localparam [15:0] INS_TUNING_x11_x1 = 16'hF6B1;
    localparam [15:0] INS_TUNING_x11_x9 = 16'hF6B9;
    localparam [15:0] INS_ADDI_x2_00  = 16'h8200;
    localparam [15:0] INS_ADDI_x13_01 = 16'h8D01;
    localparam [15:0] INS_DIR_x2_x13  = 16'hF12D;
    localparam [15:0] INS_ADDI_x3_01  = 16'h8301;
    localparam [15:0] INS_DIR_x3_x13  = 16'hF13D;
    localparam [15:0] INS_ADDI_x14_01 = 16'h8E01;
    localparam [15:0] INS_PINSEL_x3_x14 = 16'hF73E;
    localparam [15:0] INS_ADDI_x11_01 = 16'h8B01;
    localparam [15:0] INS_ADDI_x12_00 = 16'h8C00;
    localparam [15:0] INS_ADDI_x8_64  = 16'h8864;
    localparam [15:0] INS_ADDI_x5_01  = 16'h8501;
    localparam [15:0] INS_OUT_x2_x5   = 16'hF025;
    localparam [15:0] INS_OUT_x3_x5_2 = 16'hF035;
    localparam [15:0] INS_WAIT_x11_x8 = 16'hF2B8;
    localparam [15:0] INS_ADDI_x5_00  = 16'h8500;
    localparam [15:0] INS_OUT_x2_x5_2 = 16'hF025;
    localparam [15:0] INS_ADDI_x8_32  = 16'h8832;
    localparam [15:0] INS_WAIT_x11_x8_2 = 16'hF2B8;
    localparam [15:0] INS_OUT_x3_x5_3 = 16'hF035;
    localparam [15:0] INS_WAIT_x11_x8_3 = 16'hF2B8;
    localparam [15:0] INS_ADDI_x5_01_2 = 16'h8501;
    localparam [15:0] INS_OUT_x2_x5_3 = 16'hF025;
    localparam [15:0] INS_ADDI_x8_32_2 = 16'h8832;
    localparam [15:0] INS_WAIT_x11_x8_4 = 16'hF2B8;
    localparam [15:0] INS_WAIT_x11_x8_5 = 16'hF2B8;
    localparam [15:0] INS_ADDI_x5_00_2 = 16'h8500;
    localparam [15:0] INS_OUT_x2_x5_4 = 16'hF025;
    localparam [15:0] INS_WAIT_x11_x8_6 = 16'hF2B8;
    localparam [15:0] INS_WAIT_x11_x8_7 = 16'hF2B8;
    localparam [15:0] INS_ADDI_x5_01_3 = 16'h8501;
    localparam [15:0] INS_OUT_x2_x5_5 = 16'hF025;
    localparam [15:0] INS_WAIT_x11_x8_8 = 16'hF2B8;
    localparam [15:0] INS_WAIT_x11_x8_9 = 16'hF2B8;
    localparam [15:0] INS_ADDI_x5_00_3 = 16'h8500;
    localparam [15:0] INS_OUT_x2_x5_6 = 16'hF025;
    localparam [15:0] INS_WAIT_x11_x8_10 = 16'hF2B8;
    localparam [15:0] INS_WAIT_x11_x8_11 = 16'hF2B8;
    localparam [15:0] INS_ADDI_x5_00_4 = 16'h8500;
    localparam [15:0] INS_OUT_x2_x5_7 = 16'hF025;
    localparam [15:0] INS_WAIT_x11_x8_12 = 16'hF2B8;
    localparam [15:0] INS_WAIT_x11_x8_13 = 16'hF2B8;
    localparam [15:0] INS_ADDI_x5_01_4 = 16'h8501;
    localparam [15:0] INS_OUT_x2_x5_8 = 16'hF025;
    localparam [15:0] INS_WAIT_x11_x8_14 = 16'hF2B8;
    localparam [15:0] INS_WAIT_x11_x8_15 = 16'hF2B8;
    localparam [15:0] INS_ADDI_x5_00_5 = 16'h8500;
    localparam [15:0] INS_OUT_x2_x5_9 = 16'hF025;
    localparam [15:0] INS_WAIT_x11_x8_16 = 16'hF2B8;
    localparam [15:0] INS_WAIT_x11_x8_17 = 16'hF2B8;
    localparam [15:0] INS_ADDI_x5_00_6 = 16'h8500;
    localparam [15:0] INS_OUT_x2_x5_10 = 16'hF025;
    localparam [15:0] INS_WAIT_x11_x8_18 = 16'hF2B8;
    localparam [15:0] INS_WAIT_x11_x8_19 = 16'hF2B8;
    localparam [15:0] INS_ADDI_x5_01_5 = 16'h8501;
    localparam [15:0] INS_OUT_x2_x5_11 = 16'hF025;
    localparam [15:0] INS_WAIT_x11_x8_20 = 16'hF2B8;
    localparam [15:0] INS_WAIT_x11_x8_21 = 16'hF2B8;
    localparam [15:0] INS_ADDI_x5_00_7 = 16'h8500;
    localparam [15:0] INS_OUT_x3_x5_4 = 16'hF035;
    localparam [15:0] INS_WAIT_x11_x8_22 = 16'hF2B8;
    localparam [15:0] INS_ADDI_x5_00_8 = 16'h8500;
    localparam [15:0] INS_OUT_x2_x5_12 = 16'hF025;
    localparam [15:0] INS_ADDI_x5_01_6 = 16'h8501;
    localparam [15:0] INS_OUT_x3_x5_5 = 16'hF035;
    localparam [15:0] INS_WAIT_x11_x8_23 = 16'hF2B8;
    localparam [15:0] INS_OUT_x2_x5_13 = 16'hF025;
    localparam [15:0] INS_WAIT_x11_x8_24 = 16'hF2B8;
    localparam [15:0] INS_HALT = 16'hFFFF;

    initial begin
        rst_n = 0;
        wait_clk(4);
        rst_n = 1;
        wait_clk(4);

        $display("=== emu_top_ihp I²C Master Firmware Test ===");

        // Load program
        spi_write(16'h0000, {INS_ADDI_x9_1E,   INS_ADDI_x1_B8});
        spi_write(16'h0002, {INS_ADDI_x11_00,  INS_ADDI_x10_05});
        spi_write(16'h0004, {INS_ADD_x9_x9_x10, INS_ADDI_x12_03});
        spi_write(16'h0006, {INS_TCFG_x11_x12, INS_TUNING_x11_x1});
        spi_write(16'h0008, {INS_TUNING_x11_x9, INS_ADDI_x2_00});
        spi_write(16'h000A, {INS_ADDI_x13_01,  INS_DIR_x2_x13});
        spi_write(16'h000C, {INS_ADDI_x3_01,   INS_DIR_x3_x13});
        spi_write(16'h000E, {INS_ADDI_x14_01,  INS_PINSEL_x3_x14});
        spi_write(16'h0010, {INS_ADDI_x11_01,  INS_ADDI_x12_00});
        spi_write(16'h0012, {INS_ADDI_x8_64,   INS_ADDI_x5_01});
        spi_write(16'h0014, {INS_OUT_x2_x5,    INS_OUT_x3_x5_2});
        spi_write(16'h0016, {INS_WAIT_x11_x8,  INS_ADDI_x5_00});
        spi_write(16'h0018, {INS_OUT_x2_x5_2,  INS_ADDI_x8_32});
        spi_write(16'h001A, {INS_WAIT_x11_x8_2, INS_OUT_x3_x5_3});
        spi_write(16'h001C, {INS_WAIT_x11_x8_3, INS_ADDI_x5_01_2});
        spi_write(16'h001E, {INS_OUT_x2_x5_3,  INS_ADDI_x8_32_2});
        spi_write(16'h0020, {INS_WAIT_x11_x8_4, INS_WAIT_x11_x8_5});
        spi_write(16'h0022, {INS_ADDI_x5_00_2, INS_OUT_x2_x5_4});
        spi_write(16'h0024, {INS_WAIT_x11_x8_6, INS_WAIT_x11_x8_7});
        spi_write(16'h0026, {INS_ADDI_x5_01_3, INS_OUT_x2_x5_5});
        spi_write(16'h0028, {INS_WAIT_x11_x8_8, INS_WAIT_x11_x8_9});
        spi_write(16'h002A, {INS_ADDI_x5_00_3, INS_OUT_x2_x5_6});
        spi_write(16'h002C, {INS_WAIT_x11_x8_10, INS_WAIT_x11_x8_11});
        spi_write(16'h002E, {INS_ADDI_x5_00_4, INS_OUT_x2_x5_7});
        spi_write(16'h0030, {INS_WAIT_x11_x8_12, INS_WAIT_x11_x8_13});
        spi_write(16'h0032, {INS_ADDI_x5_01_4, INS_OUT_x2_x5_8});
        spi_write(16'h0034, {INS_WAIT_x11_x8_14, INS_WAIT_x11_x8_15});
        spi_write(16'h0036, {INS_ADDI_x5_00_5, INS_OUT_x2_x5_9});
        spi_write(16'h0038, {INS_WAIT_x11_x8_16, INS_WAIT_x11_x8_17});
        spi_write(16'h003A, {INS_ADDI_x5_00_6, INS_OUT_x2_x5_10});
        spi_write(16'h003C, {INS_WAIT_x11_x8_18, INS_WAIT_x11_x8_19});
        spi_write(16'h003E, {INS_ADDI_x5_01_5, INS_OUT_x2_x5_11});
        spi_write(16'h0040, {INS_WAIT_x11_x8_20, INS_WAIT_x11_x8_21});
        spi_write(16'h0042, {INS_ADDI_x5_00_7, INS_OUT_x3_x5_4});
        spi_write(16'h0044, {INS_WAIT_x11_x8_22, INS_ADDI_x5_00_8});
        spi_write(16'h0046, {INS_OUT_x2_x5_12, INS_ADDI_x5_01_6});
        spi_write(16'h0048, {INS_OUT_x3_x5_5,  INS_WAIT_x11_x8_23});
        spi_write(16'h004A, {INS_OUT_x2_x5_13, INS_WAIT_x11_x8_24});
        spi_write(16'h004C, {INS_HALT,         16'h0000});

        $display("Program loaded. Starting CPU...");
        spi_run(16'd156);

        // Wait for CPU to complete (monitor will finish when CPU halts)
        wait_clk(200000);

        $display("=== Test timed out ===");
        $finish;
    end

    // Monitor CPU running state - finish when CPU halts
    always @(posedge clk) begin
        if (dut.u_cpu.cpu_running != cpu_running_d) begin
            $display("t=%0t CPU running: %b -> %b (PC=%h)", $time, cpu_running_d, dut.u_cpu.cpu_running, dut.u_cpu.pc_debug);
            cpu_running_d = dut.u_cpu.cpu_running;
            if (!dut.u_cpu.cpu_running) begin
                $display("CPU HALTED! Finishing test.");
                $display("PC: %h", dut.u_cpu.pc_debug);
                $finish;
            end
        end
        if (dut.cpu_done != cpu_done_d) begin
            $display("t=%0t CPU done: %b -> %b", $time, cpu_done_d, dut.cpu_done);
            cpu_done_d = dut.cpu_done;
        end
    end
    reg cpu_running_d = 0;
    reg cpu_done_d = 0;

    // Timeout
    initial begin #10000000; $display("TIMEOUT"); $finish; end

endmodule
