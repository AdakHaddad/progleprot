/*
 * I²C Master Testbench - CPU Architecture
 * Tests I²C Master firmware using CPU with NCO timer for clock generation
 * 
 * I²C pins: SDA=pin0, SCL=pin1
 * Open-drain emulation: DIR=1 (output), OUT=0 (drive low), OUT=1 (release)
 * Timer 0 NCO drives SCL at ~100kHz via pin matrix
 * CPU drives SDA via OUT instructions
 */
module tb_emu_i2c_master;

    reg clk = 0;
    reg rst_n = 0;
    reg [7:0] ui_in = 8'h03;  // SDA=1, SCL=1 (idle, pulled up)
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

    // I²C firmware instructions (pre-computed 16-bit)
    // ISA encoding:
    // ADDI rd, imm:  0x8rd0 | imm8
    // ADD rd,rs1,rs2: 0x0rd0 | rs1<<4 | rs2
    // OUT pin,val:   0xF000 | pin<<4 | val
    // DIR pin,dir:   0xF100 | pin<<4 | dir
    // WAIT timer,cycles: 0xF200 | timer<<4 | cycles
    // TCFG timer,cfg: 0xF500 | timer<<4 | cfg
    // PINSEL pin,src: 0xF600 | pin<<4 | src
    // HALT:          0xFFFF

    // I²C @ 100kHz: NCO increment = (100_000 / 50_000_000) * 2^24 = 335544 = 0x51EB8
    // Low 16: 0x1EB8, High 8: 0x05
    
    // ADDI x1, 0xB8   -> 0x81B8 (NCO low)
    // ADDI x9, 0x1E   -> 0x891E (NCO mid)
    // ADDI x10, 0x05  -> 0x8A05 (NCO high)
    // ADDI x11, 0x00  -> 0x8B00 (timer 0)
    // ADDI x12, 0x03  -> 0x8C03 (MODE_NCO_CLK=3)
    // TCFG x11, x12   -> 0xF5B3 (funct=5, rs1=11, rs2=12)

    localparam [15:0] INS_ADDI_x1_B8  = 16'h81B8;
    localparam [15:0] INS_ADDI_x9_1E  = 16'h891E;
    localparam [15:0] INS_ADDI_x10_05 = 16'h8A05;
    localparam [15:0] INS_ADDI_x11_00 = 16'h8B00;
    localparam [15:0] INS_ADDI_x12_03 = 16'h8C03;
    localparam [15:0] INS_TCFG_x11_x12 = 16'hF5B3;  // TCFG timer 0, mode 3

    // Pin setup: SDA=pin0 (out), SCL=pin1 (out, NCO driven)
    localparam [15:0] INS_ADDI_x2_00  = 16'h8200;  // SDA pin
    localparam [15:0] INS_ADDI_x13_01 = 16'h8D01;  // dir = output
    localparam [15:0] INS_DIR_x2_x13  = 16'hF12D;  // DIR pin 0, dir=1
    localparam [15:0] INS_ADDI_x3_01  = 16'h8301;  // SCL pin
    localparam [15:0] INS_DIR_x3_x13  = 16'hF13D;  // DIR pin 1, dir=1
    localparam [15:0] INS_ADDI_x14_01 = 16'h8E01;  // src = Timer 0 NCO
    localparam [15:0] INS_PINSEL_x3_x14 = 16'hF63E; // PINSEL pin 1, src=1

    // Constants
    localparam [15:0] INS_ADDI_x11_01 = 16'h8B01;  // const 1
    localparam [15:0] INS_ADDI_x12_00 = 16'h8C00;  // const 0
    localparam [15:0] INS_ADDI_x8_64  = 16'h8864;  // wait 100

    // I²C idle: both high
    localparam [15:0] INS_ADDI_x5_01  = 16'h8501;  // val = 1
    localparam [15:0] INS_OUT_x2_x5   = 16'hF025;  // SDA = 1
    localparam [15:0] INS_OUT_x3_x5_2 = 16'hF035;  // SCL = 1
    localparam [15:0] INS_WAIT_x11_x8 = 16'hF2B8;  // WAIT timer 0, cycles=x8

    // START: SDA falls while SCL high
    localparam [15:0] INS_ADDI_x5_00  = 16'h8500;  // val = 0
    localparam [15:0] INS_OUT_x2_x5_2 = 16'hF025;  // SDA = 0
    localparam [15:0] INS_ADDI_x8_32  = 16'h8832;  // wait 50
    localparam [15:0] INS_WAIT_x11_x8_2 = 16'hF2B8;

    // SCL = 0
    localparam [15:0] INS_OUT_x3_x5_3 = 16'hF035;  // SCL = 0
    localparam [15:0] INS_WAIT_x11_x8_3 = 16'hF2B8;

    // Send address byte 0xA0 (8 bits)
    // Bit 7: 1 -> SDA = 1
    localparam [15:0] INS_ADDI_x5_01_2 = 16'h8501;
    localparam [15:0] INS_OUT_x2_x5_3  = 16'hF025;
    localparam [15:0] INS_ADDI_x8_32_2 = 16'h8832;
    localparam [15:0] INS_WAIT_x11_x8_4 = 16'hF2B8;
    localparam [15:0] INS_WAIT_x11_x8_5 = 16'hF2B8;

    // Bit 6: 0 -> SDA = 0
    localparam [15:0] INS_ADDI_x5_00_2 = 16'h8500;
    localparam [15:0] INS_OUT_x2_x5_4  = 16'hF025;
    localparam [15:0] INS_WAIT_x11_x8_6 = 16'hF2B8;
    localparam [15:0] INS_WAIT_x11_x8_7 = 16'hF2B8;

    // Bit 5: 1 -> SDA = 1
    localparam [15:0] INS_ADDI_x5_01_3 = 16'h8501;
    localparam [15:0] INS_OUT_x2_x5_5  = 16'hF025;
    localparam [15:0] INS_WAIT_x11_x8_8 = 16'hF2B8;
    localparam [15:0] INS_WAIT_x11_x8_9 = 16'hF2B8;

    // Bit 4: 0 -> SDA = 0
    localparam [15:0] INS_ADDI_x5_00_3 = 16'h8500;
    localparam [15:0] INS_OUT_x2_x5_6  = 16'hF025;
    localparam [15:0] INS_WAIT_x11_x8_10 = 16'hF2B8;
    localparam [15:0] INS_WAIT_x11_x8_11 = 16'hF2B8;

    // Bit 3: 0 -> SDA = 0
    localparam [15:0] INS_ADDI_x5_00_4 = 16'h8500;
    localparam [15:0] INS_OUT_x2_x5_7  = 16'hF025;
    localparam [15:0] INS_WAIT_x11_x8_12 = 16'hF2B8;
    localparam [15:0] INS_WAIT_x11_x8_13 = 16'hF2B8;

    // Bit 2: 1 -> SDA = 1
    localparam [15:0] INS_ADDI_x5_01_4 = 16'h8501;
    localparam [15:0] INS_OUT_x2_x5_8  = 16'hF025;
    localparam [15:0] INS_WAIT_x11_x8_14 = 16'hF2B8;
    localparam [15:0] INS_WAIT_x11_x8_15 = 16'hF2B8;

    // Bit 1: 0 -> SDA = 0
    localparam [15:0] INS_ADDI_x5_00_5 = 16'h8500;
    localparam [15:0] INS_OUT_x2_x5_9  = 16'hF025;
    localparam [15:0] INS_WAIT_x11_x8_16 = 16'hF2B8;
    localparam [15:0] INS_WAIT_x11_x8_17 = 16'hF2B8;

    // Bit 0: 0 -> SDA = 0
    localparam [15:0] INS_ADDI_x5_00_6 = 16'h8500;
    localparam [15:0] INS_OUT_x2_x5_10 = 16'hF025;
    localparam [15:0] INS_WAIT_x11_x8_18 = 16'hF2B8;
    localparam [15:0] INS_WAIT_x11_x8_19 = 16'hF2B8;

    // Release SDA for ACK
    localparam [15:0] INS_ADDI_x5_01_5 = 16'h8501;
    localparam [15:0] INS_OUT_x2_x5_11 = 16'hF025;
    localparam [15:0] INS_WAIT_x11_x8_20 = 16'hF2B8;
    localparam [15:0] INS_WAIT_x11_x8_21 = 16'hF2B8;

    // SCL = 0
    localparam [15:0] INS_ADDI_x5_00_7 = 16'h8500;
    localparam [15:0] INS_OUT_x3_x5_4  = 16'hF035;
    localparam [15:0] INS_WAIT_x11_x8_22 = 16'hF2B8;

    // STOP: SDA rises while SCL high
    localparam [15:0] INS_ADDI_x5_00_8 = 16'h8500;
    localparam [15:0] INS_OUT_x2_x5_12 = 16'hF025;  // SDA = 0
    localparam [15:0] INS_ADDI_x5_01_6 = 16'h8501;
    localparam [15:0] INS_OUT_x3_x5_5  = 16'hF035;  // SCL = 1
    localparam [15:0] INS_WAIT_x11_x8_23 = 16'hF2B8;
    localparam [15:0] INS_OUT_x2_x5_13 = 16'hF025;  // SDA = 1 (STOP)
    localparam [15:0] INS_WAIT_x11_x8_24 = 16'hF2B8;

    localparam [15:0] INS_HALT = 16'hFFFF;

    initial begin
        rst_n = 0;
        wait_clk(4);
        rst_n = 1;
        wait_clk(4);

        $display("=== emu_top I²C Master Firmware Test ===");

        // Load program
        spi_write(16'h0000, {INS_ADDI_x9_1E,   INS_ADDI_x1_B8});     // addr 0,1
        spi_write(16'h0002, {INS_ADDI_x11_00,  INS_ADDI_x10_05});    // addr 2,3
        spi_write(16'h0004, {INS_ADDI_x13_01,  INS_ADDI_x12_03});    // addr 4,5
        spi_write(16'h0006, {INS_TCFG_x11_x12, INS_ADDI_x2_00});     // addr 6,7
        spi_write(16'h0008, {INS_ADDI_x14_01,  INS_DIR_x2_x13});     // addr 8,9
        spi_write(16'h000A, {INS_DIR_x3_x13,   INS_PINSEL_x3_x14});  // addr 10,11
        spi_write(16'h000C, {INS_ADDI_x11_01,  INS_ADDI_x12_00});    // addr 12,13
        spi_write(16'h000E, {INS_ADDI_x8_64,   INS_ADDI_x5_01});     // addr 14,15
        spi_write(16'h0010, {INS_OUT_x2_x5,    INS_OUT_x3_x5_2});    // addr 16,17
        spi_write(16'h0012, {INS_WAIT_x11_x8,  INS_ADDI_x5_00});     // addr 18,19
        spi_write(16'h0014, {INS_OUT_x2_x5_2,  INS_ADDI_x8_32});     // addr 20,21
        spi_write(16'h0016, {INS_WAIT_x11_x8_2, INS_OUT_x3_x5_3});   // addr 22,23
        spi_write(16'h0018, {INS_WAIT_x11_x8_3, INS_ADDI_x5_01_2});  // addr 24,25
        spi_write(16'h001A, {INS_OUT_x2_x5_3,  INS_ADDI_x8_32_2});   // addr 26,27
        spi_write(16'h001C, {INS_WAIT_x11_x8_4, INS_WAIT_x11_x8_5}); // addr 28,29
        spi_write(16'h001E, {INS_ADDI_x5_00_2, INS_OUT_x2_x5_4});    // addr 30,31
        spi_write(16'h0020, {INS_WAIT_x11_x8_6, INS_WAIT_x11_x8_7}); // addr 32,33
        spi_write(16'h0022, {INS_ADDI_x5_01_3, INS_OUT_x2_x5_5});    // addr 34,35
        spi_write(16'h0024, {INS_WAIT_x11_x8_8, INS_WAIT_x11_x8_9}); // addr 36,37
        spi_write(16'h0026, {INS_ADDI_x5_00_3, INS_OUT_x2_x5_6});    // addr 38,39
        spi_write(16'h0028, {INS_WAIT_x11_x8_10, INS_WAIT_x11_x8_11}); // addr 40,41
        spi_write(16'h002A, {INS_ADDI_x5_00_4, INS_OUT_x2_x5_7});    // addr 42,43
        spi_write(16'h002C, {INS_WAIT_x11_x8_12, INS_WAIT_x11_x8_13}); // addr 44,45
        spi_write(16'h002E, {INS_ADDI_x5_01_4, INS_OUT_x2_x5_8});    // addr 46,47
        spi_write(16'h0030, {INS_WAIT_x11_x8_14, INS_WAIT_x11_x8_15}); // addr 48,49
        spi_write(16'h0032, {INS_ADDI_x5_00_5, INS_OUT_x2_x5_9});    // addr 50,51
        spi_write(16'h0034, {INS_WAIT_x11_x8_16, INS_WAIT_x11_x8_17}); // addr 52,53
        spi_write(16'h0036, {INS_ADDI_x5_00_6, INS_OUT_x2_x5_10});   // addr 54,55
        spi_write(16'h0038, {INS_WAIT_x11_x8_18, INS_WAIT_x11_x8_19}); // addr 56,57
        spi_write(16'h003A, {INS_ADDI_x5_01_5, INS_OUT_x2_x5_11});   // addr 58,59
        spi_write(16'h003C, {INS_WAIT_x11_x8_20, INS_WAIT_x11_x8_21}); // addr 60,61
        spi_write(16'h003E, {INS_ADDI_x5_00_7, INS_OUT_x3_x5_4});    // addr 62,63
        spi_write(16'h0040, {INS_WAIT_x11_x8_22, INS_ADDI_x5_00_8}); // addr 64,65
        spi_write(16'h0042, {INS_OUT_x2_x5_12,  INS_ADDI_x5_01_6});  // addr 66,67
        spi_write(16'h0044, {INS_OUT_x3_x5_5,   INS_WAIT_x11_x8_23}); // addr 68,69
        spi_write(16'h0046, {INS_OUT_x2_x5_13,  INS_WAIT_x11_x8_24}); // addr 70,71
        spi_write(16'h0048, {INS_HALT,          16'h0000});           // addr 72,73

        $display("Program loaded. Starting CPU...");
        spi_run(16'd148);  // 74 instructions * 2 bytes

        // Wait for CPU to complete
        wait_clk(2000000);

        $display("=== CPU Registers ===");
        // Use debug register read port
        dbg_reg_idx = 4'd0; wait_clk(1); $display("R0 (x0): %h", dbg_reg_data);
        dbg_reg_idx = 4'd1; wait_clk(1); $display("R1 (x1): %h (NCO low)", dbg_reg_data);
        dbg_reg_idx = 4'd2; wait_clk(1); $display("R2 (x2): %h (SDA pin)", dbg_reg_data);
        dbg_reg_idx = 4'd3; wait_clk(1); $display("R3 (x3): %h (SCL pin)", dbg_reg_data);
        dbg_reg_idx = 4'd4; wait_clk(1); $display("R4 (x4): %h (slave addr)", dbg_reg_data);
        dbg_reg_idx = 4'd5; wait_clk(1); $display("R5 (x5): %h (data/val)", dbg_reg_data);
        dbg_reg_idx = 4'd8; wait_clk(1); $display("R8 (x8): %h (wait)", dbg_reg_data);
        dbg_reg_idx = 4'd9; wait_clk(1); $display("R9 (x9): %h (NCO mid)", dbg_reg_data);
        dbg_reg_idx = 4'd10; wait_clk(1); $display("R10 (x10): %h (NCO high)", dbg_reg_data);
        dbg_reg_idx = 4'd11; wait_clk(1); $display("R11 (x11): %h (timer/const1)", dbg_reg_data);
        dbg_reg_idx = 4'd12; wait_clk(1); $display("R12 (x12): %h (const0/mode)", dbg_reg_data);
        dbg_reg_idx = 4'd13; wait_clk(1); $display("R13 (x13): %h (dir)", dbg_reg_data);
        dbg_reg_idx = 4'd14; wait_clk(1); $display("R14 (x14): %h (pin sel src)", dbg_reg_data);
        dbg_reg_idx = 4'd15; wait_clk(1); $display("R15 (x15): %h", dbg_reg_data);
        $display("PC: %h", dut.u_cpu.pc_debug);
        
        $display("=== Pin Status ===");
        $display("Pin 0 (SDA) out: %b, OE: %b", uo_out[0], uio_oe[0]);
        $display("Pin 1 (SCL) out: %b, OE: %b", uo_out[1], uio_oe[1]);
        $display("Pin 0 in: %b, Pin 1 in: %b", ui_in[0], ui_in[1]);
        
        $display("=== Timer Status ===");
        $display("Timer 0 NCO clk: %b", dut.u_timers.nco_clk_out[0]);
        $display("Timer 0 mode: %h", dut.u_timers.mode[0]);
        $display("Timer 0 tuning: %h", dut.u_timers.tuning_word[0]);

        $display("=== Test Complete ===");
        $finish;
    end

    // Monitor I²C pins
    always @(posedge clk) begin
        if (uio_oe[0] || uio_oe[1]) begin
            $display("t=%0t I2C: SDA_oe=%b SDA_out=%b SCL_oe=%b SCL_out=%b (PC=%h) nco=%b phase=%h", 
                     $time, uio_oe[0], uo_out[0], uio_oe[1], uo_out[1], dut.u_cpu.pc_debug, 
                     dut.u_timers.nco_clk_out[0], dut.u_timers.phase_acc[0]);
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

    // Timeout
    initial begin #1000000; $display("TIMEOUT"); $finish; end

endmodule
