/*
 * Testbench for UART firmware on emu_top CPU architecture
 * Tests UART TX at 3Mbps using NCO timer
 */
module tb_emu_uart;

    reg clk = 0;
    reg rst_n = 0;
    reg [7:0] ui_in = 8'h00;
    reg [7:0] uio_in = 8'hFF;  // SPI idle: SCK=1, MOSI=1, CS_N=1
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    // Debug register interface
    reg [3:0] dbg_reg_idx = 4'd0;
    wire [15:0] dbg_reg_data;

    // Instantiate the CPU-based top module
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

    always #10 clk = ~clk;  // 50MHz = 20ns period

    // SPI host interface helpers
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
            cmd = make_spi_cmd(data, addr, 8'h01);  // CMD_WRITE = 0x01
            uio_in[2] = 0;  // CS_N low
            wait_clk(2);
            for (b = 63; b >= 0; b = b - 1) begin
                uio_in[1] = cmd[b];  // MOSI
                uio_in[0] = 0; wait_clk(2);  // SCK low
                uio_in[0] = 1; wait_clk(2);  // SCK high
            end
            uio_in[2] = 1;  // CS_N high
            wait_clk(4);
        end
    endtask

    task spi_run(input [15:0] length);
        integer b;
        reg [63:0] cmd;
        begin
            cmd = make_spi_cmd(32'h0, length, 8'h03);  // CMD_RUN = 0x03
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

    // UART firmware instructions (pre-computed 16-bit)
    // ISA encoding:
    // ADDI rd, imm:  0x8rd0 | imm8
    // ADD rd,rs1,rs2: 0x0rd0 | rs1<<4 | rs2
    // OUT pin,val:   0xF000 | pin<<4 | val
    // DIR pin:       0xF100 | pin<<4
    // WAIT timer,cycles: 0xF200 | timer<<4 | cycles
    // HALT:          0xFFFF

    // ADDI x1, 0x29   -> 0x8129
    // ADDI x2, 0x5C   -> 0x825C
    // ADDI x3, 0x0F   -> 0x830F
    // ADDI x4, 0x00   -> 0x8400
    // ADDI x5, 0x00   -> 0x8500 (pin 0)
    // DIR x5          -> 0xF150 (funct=1, rs1=5)
    // ADDI x6, 0x01   -> 0x8601 (pin 1)
    // DIR x6          -> 0xF160 (but DIR with rs2=0 means input? Let's use 0xF160)
    // ADDI x7, 0x55   -> 0x8755
    // ADDI x8, 0x00   -> 0x8800
    // ADDI x9, 0x0A   -> 0x890A
    // ADDI x10, 0x00  -> 0x8A00
    // ADDI x11, 0x01  -> 0x8B01
    
    // TX loop:
    // ADDI x7, 0x00   -> 0x8700 (start bit)
    // OUT x5, x7      -> 0xF057 (funct=0, rs1=5, rs2=7)
    // ADDI x4, 0x00   -> 0x8400 (timer 0)
    // ADDI x8, 0x11   -> 0x8811 (17 cycles)
    // WAIT x4, x8     -> 0xF248 (funct=2, rs1=4, rs2=8)
    // ... data bits ...
    // HALT            -> 0xFFFF

    localparam [15:0] INS_ADDI_x1_29  = 16'h8129;
    localparam [15:0] INS_ADDI_x2_5C  = 16'h825C;
    localparam [15:0] INS_ADDI_x3_0F  = 16'h830F;
    localparam [15:0] INS_ADDI_x4_00  = 16'h8400;
    localparam [15:0] INS_ADDI_x5_00  = 16'h8500;
    localparam [15:0] INS_DIR_x5      = 16'hF150;   // DIR pin 5 (x5=0 -> pin 0)
    localparam [15:0] INS_ADDI_x6_01  = 16'h8601;
    localparam [15:0] INS_DIR_x6      = 16'hF160;
    localparam [15:0] INS_ADDI_x7_55  = 16'h8755;
    localparam [15:0] INS_ADDI_x8_00  = 16'h8800;
    localparam [15:0] INS_ADDI_x9_0A  = 16'h890A;
    localparam [15:0] INS_ADDI_x10_00 = 16'h8A00;
    localparam [15:0] INS_ADDI_x11_01 = 16'h8B01;

    // TX start bit
    localparam [15:0] INS_ADDI_x7_00  = 16'h8700;
    localparam [15:0] INS_OUT_x5_x7   = 16'hF057;   // OUT pin(x5), val(x7)
    localparam [15:0] INS_ADDI_x4_00_2= 16'h8400;
    localparam [15:0] INS_ADDI_x8_11  = 16'h8811;
    localparam [15:0] INS_WAIT_x4_x8  = 16'hF248;

    // Data bit 0 (1)
    localparam [15:0] INS_ADDI_x7_01  = 16'h8701;
    localparam [15:0] INS_OUT_x5_x7_2 = 16'hF057;

    // Data bit 1 (0)
    localparam [15:0] INS_ADDI_x7_00_2= 16'h8700;

    // ... more bits ...
    localparam [15:0] INS_HALT        = 16'hFFFF;

    initial begin
        rst_n = 0;
        wait_clk(4);
        rst_n = 1;
        wait_clk(4);

        $display("=== emu_top UART Firmware Test ===");

        // Load program: 12 init instructions + TX loop
        spi_write(16'h0000, {INS_ADDI_x2_5C,  INS_ADDI_x1_29});   // addr 0,1
        spi_write(16'h0002, {INS_ADDI_x4_00,  INS_ADDI_x3_0F});   // addr 2,3
        spi_write(16'h0004, {INS_ADDI_x6_01,  INS_ADDI_x5_00});   // addr 4,5
        spi_write(16'h0006, {INS_ADDI_x8_00,  INS_ADDI_x7_55});   // addr 6,7
        spi_write(16'h0008, {INS_ADDI_x10_00, INS_ADDI_x9_0A});   // addr 8,9
        spi_write(16'h000A, {INS_DIR_x5,      INS_ADDI_x11_01});   // addr 10,11
        spi_write(16'h000C, {INS_DIR_x6,      INS_ADDI_x4_00_2});  // addr 12,13
        spi_write(16'h000E, {INS_ADDI_x8_11,  INS_ADDI_x7_00});   // addr 14,15
        spi_write(16'h0010, {INS_OUT_x5_x7,   INS_WAIT_x4_x8});   // addr 16,17
        spi_write(16'h0012, {INS_ADDI_x7_01,  INS_OUT_x5_x7_2});  // addr 18,19
        spi_write(16'h0014, {INS_WAIT_x4_x8,  INS_ADDI_x7_00_2}); // addr 20,21
        spi_write(16'h0016, {INS_HALT,        16'h0000});         // addr 22,23

        $display("Program loaded. Starting CPU...");
        spi_run(16'd48);  // 24 instructions * 2 bytes

        // Wait for CPU to complete
        wait_clk(100000);

        $display("=== CPU Registers ===");
        // Use debug register read port
        dbg_reg_idx = 4'd0; wait_clk(1); $display("R0 (x0): %h", dbg_reg_data);
        dbg_reg_idx = 4'd1; wait_clk(1); $display("R1 (x1): %h (NCO inc low)", dbg_reg_data);
        dbg_reg_idx = 4'd2; wait_clk(1); $display("R2 (x2): %h (NCO inc mid)", dbg_reg_data);
        dbg_reg_idx = 4'd3; wait_clk(1); $display("R3 (x3): %h (NCO inc high)", dbg_reg_data);
        dbg_reg_idx = 4'd5; wait_clk(1); $display("R5 (x5): %h (TX pin)", dbg_reg_data);
        dbg_reg_idx = 4'd7; wait_clk(1); $display("R7 (x7): %h (TX data)", dbg_reg_data);
        $display("PC: %h", dut.u_cpu.pc_debug);
        $display("Pin 0 out: %b, Pin 0 OE: %b", uo_out[0], uio_oe[0]);

        $display("=== Test Complete ===");
        $finish;
    end

    // Monitor TX pin
    always @(posedge clk) begin
        if (dut.u_cpu.cpu_running && uio_oe[0]) begin
            $display("t=%0t TX pin 0: %b", $time, uo_out[0]);
        end
    end

    initial begin #5000000; $display("TIMEOUT"); $finish; end

endmodule
