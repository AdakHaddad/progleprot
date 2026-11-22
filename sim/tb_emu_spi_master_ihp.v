/*
 * SPI Master Testbench - CPU Architecture with IHP SRAM
 * Tests SPI Master firmware using CPU with NCO timer for clock generation
 */
module tb_emu_spi_master_ihp;

    reg clk = 0;
    reg rst_n = 0;
    reg [7:0] ui_in = 8'h00;
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

    // SPI Master firmware instructions
    localparam [15:0] INS_ADDI_x1_00   = 16'h8100;
    localparam [15:0] INS_ADDI_x2_00   = 16'h8200;
    localparam [15:0] INS_ADDI_x3_00   = 16'h8300;
    localparam [15:0] INS_ADDI_x4_00_A = 16'h8400;
    localparam [15:0] INS_ADDI_x5_01   = 16'h8501;
    localparam [15:0] INS_ADDI_x6_02   = 16'h8602;
    localparam [15:0] INS_ADDI_x7_03   = 16'h8703;
    localparam [15:0] INS_ADDI_x8_00   = 16'h8800;
    localparam [15:0] INS_ADDI_x9_00   = 16'h8900;
    localparam [15:0] INS_ADDI_x10_00  = 16'h8A00;
    localparam [15:0] INS_ADDI_x11_00  = 16'h8B00;
    localparam [15:0] INS_ADDI_x12_00  = 16'h8C00;
    localparam [15:0] INS_ADDI_x13_00  = 16'h8D00;
    localparam [15:0] INS_ADDI_x14_00  = 16'h8E00;
    localparam [15:0] INS_ADDI_x15_00  = 16'h8F00;

    localparam [15:0] INS_DIR_x5       = 16'hF150;  // MOSI output
    localparam [15:0] INS_DIR_x6       = 16'hF160;  // MISO input
    localparam [15:0] INS_DIR_x7       = 16'hF170;  // SCK output
    localparam [15:0] INS_DIR_x8       = 16'hF180;  // CS output

    localparam [15:0] INS_PINSEL_x7_x1 = 16'hF771;  // SCK (pin 7) = Timer 0 NCO

    localparam [15:0] INS_TCFG_x1_03   = 16'hF513;  // Timer 0: NCO_CLK mode
    localparam [15:0] INS_TUNING_x1_x9 = 16'hF619;  // Timer 0 tuning

    localparam [15:0] INS_ADDI_x1_0A   = 16'h810A;  // 10 bits to send
    localparam [15:0] INS_ADDI_x2_A5   = 16'h82A5;  // Data pattern 0xA5
    localparam [15:0] INS_ADDI_x3_01   = 16'h8301;
    localparam [15:0] INS_ADDI_x4_00_B = 16'h8400;
    localparam [15:0] INS_OUT_x8_x3    = 16'hF083;  // CS low
    localparam [15:0] INS_OUT_x5_x2    = 16'hF052;  // MOSI bit
    localparam [15:0] INS_WAIT_x1_x4   = 16'hF214;  // Wait for SCK
    localparam [15:0] INS_ADDI_x2_x2_x2 = 16'h0222; // Shift data
    localparam [15:0] INS_ADDI_x1_x1_01 = 16'h0111; // Decrement bit count
    localparam [15:0] INS_BNEZ_x1_LOOP = 16'hB1FA;  // Branch if not zero

    localparam [15:0] INS_OUT_x8_x4    = 16'hF084;  // CS high
    localparam [15:0] INS_HALT         = 16'hFFFF;

    initial begin
        rst_n = 0;
        wait_clk(4);
        rst_n = 1;
        wait_clk(4);

        $display("=== emu_top_ihp SPI Master Firmware Test ===");

        // Load program
        spi_write(16'h0000, {INS_ADDI_x1_00,  INS_ADDI_x2_00});
        spi_write(16'h0002, {INS_ADDI_x3_00,  INS_ADDI_x4_00_A});
        spi_write(16'h0004, {INS_ADDI_x5_01,  INS_ADDI_x6_02});
        spi_write(16'h0006, {INS_ADDI_x7_03,  INS_ADDI_x8_00});
        spi_write(16'h0008, {INS_ADDI_x9_00,  INS_ADDI_x10_00});
        spi_write(16'h000A, {INS_ADDI_x11_00, INS_ADDI_x12_00});
        spi_write(16'h000C, {INS_ADDI_x13_00, INS_ADDI_x14_00});
        spi_write(16'h000E, {INS_ADDI_x15_00, INS_DIR_x5});
        spi_write(16'h0010, {INS_DIR_x6,      INS_DIR_x7});
        spi_write(16'h0012, {INS_DIR_x8,      INS_PINSEL_x7_x1});
        spi_write(16'h0014, {INS_TCFG_x1_03,  INS_TUNING_x1_x9});
        spi_write(16'h0016, {INS_ADDI_x1_0A,  INS_ADDI_x2_A5});
        spi_write(16'h0018, {INS_ADDI_x3_01,  INS_ADDI_x4_00_B});
        spi_write(16'h001A, {INS_OUT_x8_x3,   INS_OUT_x5_x2});
        spi_write(16'h001C, {INS_WAIT_x1_x4,  INS_ADDI_x2_x2_x2});
        spi_write(16'h001E, {INS_ADDI_x1_x1_01, INS_BNEZ_x1_LOOP});
        spi_write(16'h0020, {INS_OUT_x8_x4,   INS_HALT});

        $display("Program loaded. Starting CPU...");
        spi_run(16'd68);  // 34 instructions

        wait_clk(50000);

        $display("=== Test Complete ===");
        $finish;
    end

    // Monitor
    always @(posedge clk) begin
        if (dut.u_cpu.cpu_running) begin
            if (uio_oe[0]) $display("t=%0t MOSI=%b", $time, uo_out[0]);
            if (uio_oe[2]) $display("t=%0t SCK=%b", $time, uo_out[2]);
            if (uio_oe[3]) $display("t=%0t CS=%b", $time, uo_out[3]);
        end
    end

    initial begin #5000000; $display("TIMEOUT"); $finish; end

endmodule
