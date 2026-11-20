/*
 * Testbench for SPI Master firmware on emu_top CPU architecture
 * Tests SPI TX at 25MHz using NCO timer
 * SPI pins: MOSI=pin0, MISO=pin1, SCK=pin2, CS=pin3
 */
module tb_emu_spi_master;

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

    // SPI Master firmware instructions (pre-computed 16-bit)
    // ISA encoding:
    // ADDI rd, imm:  0x8rd0 | imm8
    // ADD rd,rs1,rs2: 0x0rd0 | rs1<<4 | rs2
    // OUT pin,val:   0xF000 | pin<<4 | val
    // DIR pin,dir:   0xF100 | pin<<4 | dir
    // WAIT timer,cycles: 0xF200 | timer<<4 | cycles
    // TCFG timer,cfg: 0xF500 | timer<<4 | cfg
    // TUNING timer,val: 0xF600 | timer<<4 | val   (funct=6)
    // PINSEL pin,src: 0xF700 | pin<<4 | src      (funct=7)
    // HALT:          0xFFFF

    // SPI Master @ 25MHz: NCO increment = (25_000_000 / 50_000_000) * 2^24 = 0x800000
    // Timer 0 NCO: 0x800000 (low 16: 0x0000, mid 8: 0x80, high 8: 0x00)
    
    // ADDI x1, 0x00   -> 0x8100 (NCO low 8 bits)
    // ADDI x2, 0x80   -> 0x8280 (NCO mid 8 bits)
    // ADDI x3, 0x00   -> 0x8300 (NCO high 8 bits)
    // ADDI x4, 0x00   -> 0x8400 (timer 0)
    // ADDI x5, 0x00   -> 0x8500 (pin 0 = MOSI)
    // ADDI x6, 0x02   -> 0x8602 (pin 2 = SCK)
    // ADDI x7, 0x03   -> 0x8703 (pin 3 = CS)
    // ADDI x8, 0x01   -> 0x8801 (pin 1 = MISO - input)
    // ADDI x9, 0xAA   -> 0x89AA (TX data = 0xAA)
    // ADDI x10, 0x08  -> 0x8A08 (bit count = 8)
    // ADDI x11, 0x01  -> 0x8B01 (const 1)
    // ADDI x12, 0x00  -> 0x8C00
    // ADDI x13, 0x11  -> 0x8D11 (wait cycles ~17)
    // ADDI x14, 0x01  -> 0x8E01 (for PINSEL src)
    // ADDI x15, 0x00  -> 0x8F00

    localparam [15:0] INS_ADDI_x1_00  = 16'h8100;
    localparam [15:0] INS_ADDI_x2_80  = 16'h8280;
    localparam [15:0] INS_ADDI_x3_00  = 16'h8300;
    localparam [15:0] INS_ADDI_x4_00  = 16'h8400;
    localparam [15:0] INS_ADDI_x5_00  = 16'h8500;
    localparam [15:0] INS_ADDI_x6_02  = 16'h8602;
    localparam [15:0] INS_ADDI_x7_03  = 16'h8703;
    localparam [15:0] INS_ADDI_x8_01  = 16'h8801;
    localparam [15:0] INS_ADDI_x9_AA  = 16'h89AA;
    localparam [15:0] INS_ADDI_x10_08 = 16'h8A08;
    localparam [15:0] INS_ADDI_x11_01 = 16'h8B01;
    localparam [15:0] INS_ADDI_x12_00 = 16'h8C00;
    localparam [15:0] INS_ADDI_x13_11 = 16'h8D11;
    localparam [15:0] INS_ADDI_x14_01 = 16'h8E01;
    localparam [15:0] INS_ADDI_x15_00 = 16'h8F00;

    // TUNING writes for NCO (funct=6)
    // TUNING x4, x1  -> write low 8 bits to REG_TUNING (rs2[8]=0)
    // TUNING x4, x2  -> write mid 8 bits 
    // TUNING x4, x3  -> write high 8 bits (need rs2[8]=1 for REG_TUNING_H)
    // x15 = 0x100 (bit 8 = 1 for high reg)
    localparam [15:0] INS_ADDI_x15_100 = 16'h8F00;
    localparam [15:0] INS_TUNING_x4_x1  = 16'hF641;  // TUNING timer 0, val=x1 (low 8)
    localparam [15:0] INS_TUNING_x4_x2  = 16'hF642;  // TUNING timer 0, val=x2 (mid 8) 
    localparam [15:0] INS_TUNING_x4_x15 = 16'hF64F; // TUNING timer 0, val=x15 (high 16 with bit 8=1)

    // TCFG: configure timer 0 as NCO clock (MODE_NCO_CLK = 3)
    localparam [15:0] INS_ADDI_x12_03  = 16'h8C03;
    localparam [15:0] INS_TCFG_x4_x12  = 16'hF543;  // TCFG timer 0, mode 3

    // DIR pins: 0=MOSI(out), 2=SCK(out), 3=CS(out), 1=MISO(in)
    localparam [15:0] INS_ADDI_x13_01  = 16'h8D01;  // dir = output
    localparam [15:0] INS_DIR_x5_x13   = 16'hF15D;  // DIR pin 0 (MOSI), dir=1
    localparam [15:0] INS_DIR_x6_x13   = 16'hF16D;  // DIR pin 2 (SCK), dir=1
    localparam [15:0] INS_DIR_x7_x13   = 16'hF17D;  // DIR pin 3 (CS), dir=1
    localparam [15:0] INS_ADDI_x13_00  = 16'h8D00;  // dir = input
    localparam [15:0] INS_DIR_x8_x13   = 16'hF18D;  // DIR pin 1 (MISO), dir=0

    // PINSEL: SCK (pin 2) driven by Timer 0 NCO (src=1)
    localparam [15:0] INS_PINSEL_x6_x14 = 16'hF76E; // PINSEL pin 2, src=1 (funct=7!)

    // CS low
    localparam [15:0] INS_ADDI_x7_00  = 16'h8700;
    localparam [15:0] INS_OUT_x7_x7   = 16'hF077;  // OUT pin 3 (CS), val=0

    // SCK idle high (mode 0) - will be overridden by NCO
    localparam [15:0] INS_ADDI_x6_01  = 16'h8601;
    localparam [15:0] INS_OUT_x6_x6   = 16'hF066;  // OUT pin 2 (SCK), val=1

    // TX loop start
    localparam [15:0] INS_ADDI_x10_08_2 = 16'h8A08; // reset bit count
    localparam [15:0] INS_ADDI_x9_AA_2  = 16'h89AA; // reload data

    // Bit loop: check MSB, output to MOSI
    localparam [15:0] INS_ADD_x12_x9_x0 = 16'h0C90; // ADD x12, x9, x0 (shift)
    localparam [15:0] INS_ADDI_x12_01  = 16'h8C01; // check MSB

    // SCK low (NCO will drive this)
    localparam [15:0] INS_ADDI_x6_00  = 16'h8600;
    localparam [15:0] INS_OUT_x6_x6_2 = 16'hF066;

    // Wait half cycle
    localparam [15:0] INS_WAIT_x4_x13 = 16'hF24D;  // WAIT timer 0, cycles=x13

    // SCK high (NCO will drive this)
    localparam [15:0] INS_ADDI_x6_01_2 = 16'h8601;
    localparam [15:0] INS_OUT_x6_x6_3 = 16'hF066;

    // Wait half cycle
    localparam [15:0] INS_WAIT_x4_x13_2 = 16'hF24D;

    // Shift left
    localparam [15:0] INS_ADD_x9_x9_x9 = 16'h0999;  // ADD x9, x9, x9 (shift left)

    // Decrement bit count
    localparam [15:0] INS_ADDI_x10_ff = 16'h8AFF;  // ADDI x10, -1
    localparam [15:0] INS_ADD_x10_x10_x11 = 16'h0AAE; // ADD x10, x10, x11 (decrement)

    // Branch if not zero (simplified - use HALT for now)
    localparam [15:0] INS_HALT        = 16'hFFFF;

    initial begin
        rst_n = 0;
        wait_clk(4);
        rst_n = 1;
        wait_clk(4);

        $display("=== emu_top SPI Master Firmware Test ===");

        // Load program
        spi_write(16'h0000, {INS_ADDI_x2_80,  INS_ADDI_x1_00});   // addr 0,1
        spi_write(16'h0002, {INS_ADDI_x4_00,  INS_ADDI_x3_00});   // addr 2,3
        spi_write(16'h0004, {INS_ADDI_x6_02,  INS_ADDI_x5_00});   // addr 4,5
        spi_write(16'h0006, {INS_ADDI_x8_01,  INS_ADDI_x7_03});   // addr 6,7
        spi_write(16'h0008, {INS_ADDI_x10_08, INS_ADDI_x9_AA});   // addr 8,9
        spi_write(16'h000A, {INS_ADDI_x12_00, INS_ADDI_x11_01});  // addr 10,11
        spi_write(16'h000C, {INS_ADDI_x14_01, INS_ADDI_x13_11});  // addr 12,13
        spi_write(16'h000E, {INS_ADDI_x15_00, INS_ADDI_x15_100}); // addr 14,15 (x15=0, x15=0x100)
        spi_write(16'h0010, {INS_TUNING_x4_x1,  INS_TUNING_x4_x2}); // addr 16,17 (NCO low, mid)
        spi_write(16'h0012, {INS_TUNING_x4_x15, INS_TCFG_x4_x12}); // addr 18,19 (NCO high, mode)
        spi_write(16'h0014, {INS_ADDI_x5_00,  INS_ADDI_x13_01});  // addr 20,21 (pin 0, dir=out)
        spi_write(16'h0016, {INS_DIR_x5_x13,  INS_ADDI_x6_02});   // addr 22,23
        spi_write(16'h0018, {INS_DIR_x6_x13,  INS_ADDI_x7_03});   // addr 24,25
        spi_write(16'h001A, {INS_DIR_x7_x13,  INS_ADDI_x8_01});   // addr 26,27
        spi_write(16'h001C, {INS_ADDI_x13_00, INS_DIR_x8_x13});   // addr 28,29
        spi_write(16'h001E, {INS_ADDI_x14_01, INS_PINSEL_x6_x14}); // addr 30,31 (pin sel SCK)
        spi_write(16'h0020, {INS_ADDI_x7_00,  INS_OUT_x7_x7});    // addr 32,33 (CS low)
        spi_write(16'h0022, {INS_ADDI_x6_01,  INS_OUT_x6_x6});    // addr 34,35 (SCK idle)
        spi_write(16'h0024, {INS_ADDI_x10_08_2, INS_ADDI_x9_AA_2}); // addr 36,37
        spi_write(16'h0026, {INS_ADD_x12_x9_x0, INS_ADDI_x12_01}); // addr 38,39
        spi_write(16'h0028, {INS_ADDI_x6_00,  INS_OUT_x6_x6_2});  // addr 40,41
        spi_write(16'h002A, {INS_WAIT_x4_x13, INS_ADDI_x6_01_2}); // addr 42,43
        spi_write(16'h002C, {INS_OUT_x6_x6_3, INS_WAIT_x4_x13_2}); // addr 44,45
        spi_write(16'h002E, {INS_ADD_x9_x9_x9,  INS_ADDI_x10_ff}); // addr 46,47
        spi_write(16'h0030, {INS_ADD_x10_x10_x11, INS_HALT});    // addr 48,49

        $display("Program loaded. Starting CPU...");
        spi_run(16'd100);  // 50 instructions * 2 bytes

        // Wait for CPU to complete
        wait_clk(500000);

        $display("=== CPU Registers ===");
        // Use debug register read port
        dbg_reg_idx = 4'd0; wait_clk(1); $display("R0 (x0): %h", dbg_reg_data);
        dbg_reg_idx = 4'd1; wait_clk(1); $display("R1 (x1): %h (NCO low)", dbg_reg_data);
        dbg_reg_idx = 4'd2; wait_clk(1); $display("R2 (x2): %h (NCO mid)", dbg_reg_data);
        dbg_reg_idx = 4'd3; wait_clk(1); $display("R3 (x3): %h (NCO high)", dbg_reg_data);
        dbg_reg_idx = 4'd5; wait_clk(1); $display("R5 (x5): %h (MOSI pin)", dbg_reg_data);
        dbg_reg_idx = 4'd6; wait_clk(1); $display("R6 (x6): %h (SCK pin)", dbg_reg_data);
        dbg_reg_idx = 4'd7; wait_clk(1); $display("R7 (x7): %h (CS pin)", dbg_reg_data);
        dbg_reg_idx = 4'd9; wait_clk(1); $display("R9 (x9): %h (TX data)", dbg_reg_data);
        dbg_reg_idx = 4'd10; wait_clk(1); $display("R10 (x10): %h (bit cnt)", dbg_reg_data);
        dbg_reg_idx = 4'd11; wait_clk(1); $display("R11 (x11): %h (const1)", dbg_reg_data);
        dbg_reg_idx = 4'd12; wait_clk(1); $display("R12 (x12): %h (shift)", dbg_reg_data);
        dbg_reg_idx = 4'd13; wait_clk(1); $display("R13 (x13): %h (wait)", dbg_reg_data);
        dbg_reg_idx = 4'd14; wait_clk(1); $display("R14 (x14): %h (pin sel src)", dbg_reg_data);
        dbg_reg_idx = 4'd15; wait_clk(1); $display("R15 (x15): %h (const0/tuning)", dbg_reg_data);
        $display("PC: %h", dut.u_cpu.pc_debug);
        
        $display("=== Pin Status ===");
        $display("Pin 0 (MOSI) out: %b, OE: %b", uo_out[0], uio_oe[0]);
        $display("Pin 1 (MISO) out: %b, OE: %b", uo_out[1], uio_oe[1]);
        $display("Pin 2 (SCK) out: %b, OE: %b", uo_out[2], uio_oe[2]);
        $display("Pin 3 (CS) out: %b, OE: %b", uo_out[3], uio_oe[3]);
        
        $display("=== Timer Status ===");
        $display("Timer 0 NCO clk: %b", dut.u_timers.nco_clk_out[0]);
        $display("Timer 0 mode: %h", dut.u_timers.mode[0]);
        $display("Timer 0 tuning: %h", dut.u_timers.tuning_word[0]);

        $display("=== Test Complete ===");
        $finish;
    end

    // Monitor SPI pins
    always @(posedge clk) begin
        if (dut.u_cpu.cpu_running && (uio_oe[0] || uio_oe[2] || uio_oe[3])) begin
            $display("t=%0t MOSI=%b SCK=%b CS=%b (PC=%h) nco=%b", 
                     $time, uo_out[0], uo_out[2], uo_out[3], dut.u_cpu.pc_debug, 
                     dut.u_timers.nco_clk_out[0]);
        end
    end

    // Monitor CPU pin writes
    always @(posedge clk) begin
        if (dut.u_cpu.cpu_running && dut.u_cpu.pin_wr_en) begin
            $display("t=%0t CPU PIN WR: addr=%h data=%h (PC=%h)", 
                     $time, dut.u_cpu.pin_wr_addr, dut.u_cpu.pin_wr_data, dut.u_cpu.pc_debug);
        end
    end

    // Monitor Timer writes
    always @(posedge clk) begin
        if (dut.u_cpu.cpu_running && dut.u_cpu.timer_wr_en) begin
            $display("t=%0t CPU TIMER WR: addr=%h data=%h (PC=%h)", 
                     $time, dut.u_cpu.timer_wr_addr, dut.u_cpu.timer_wr_data, dut.u_cpu.pc_debug);
        end
    end

    initial begin #5000000; $display("TIMEOUT"); $finish; end

endmodule
