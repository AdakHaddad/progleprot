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

    // Instruction encoding for CPU ISA
    function [15:0] INS_ADDI(input [3:0] rd, input [7:0] imm);
        begin INS_ADDI = (4'h8 << 12) | (rd << 8) | imm; end
    endfunction

    function [15:0] INS_ORI(input [3:0] rd, input [7:0] imm);
        begin INS_ORI = (4'h9 << 12) | (rd << 8) | imm; end
    endfunction

    function [15:0] INS_ADD(input [3:0] rd, input [3:0] rs1, input [3:0] rs2);
        begin INS_ADD = (4'h0 << 12) | (rd << 8) | (rs1 << 4) | rs2; end
    endfunction

    // Custom instruction funct codes
    localparam FUNCT_OUT    = 4'h0;
    localparam FUNCT_DIR    = 4'h1;
    localparam FUNCT_WAIT   = 4'h2;
    localparam FUNCT_TCFG   = 4'h5;
    localparam FUNCT_TUNING = 4'h6;
    localparam FUNCT_PINSEL = 4'h7;
    localparam FUNCT_HALT   = 4'hF;

    function [15:0] INS_OUT(input [3:0] pin_reg, input [3:0] val_reg);
        begin INS_OUT = (4'hF << 12) | (FUNCT_OUT << 8) | (pin_reg << 4) | val_reg; end
    endfunction

    function [15:0] INS_DIR(input [3:0] pin_reg, input [3:0] dir_reg);
        begin INS_DIR = (4'hF << 12) | (FUNCT_DIR << 8) | (pin_reg << 4) | dir_reg; end
    endfunction

    function [15:0] INS_WAIT(input [3:0] timer_reg, input [3:0] cycles_reg);
        begin INS_WAIT = (4'hF << 12) | (FUNCT_WAIT << 8) | (timer_reg << 4) | cycles_reg; end
    endfunction

    function [15:0] INS_TCFG(input [3:0] timer_reg, input [3:0] config_reg);
        begin INS_TCFG = (4'hF << 12) | (FUNCT_TCFG << 8) | (timer_reg << 4) | config_reg; end
    endfunction

    function [15:0] INS_TUNING(input [3:0] timer_reg, input [3:0] tuning_reg);
        begin INS_TUNING = (4'hF << 12) | (FUNCT_TUNING << 8) | (timer_reg << 4) | tuning_reg; end
    endfunction

    function [15:0] INS_PINSEL(input [3:0] pin_reg, input [3:0] src_reg);
        begin INS_PINSEL = (4'hF << 12) | (FUNCT_PINSEL << 8) | (pin_reg << 4) | src_reg; end
    endfunction

    function [15:0] INS_HALT();
        begin INS_HALT = 16'hFFFF; end
    endfunction

    function [15:0] INS_NOP();
        begin INS_NOP = 16'h0000; end
    endfunction

    // ============================================================
    // Initial block: Load I²C Master firmware and start CPU
    // ============================================================
    initial begin
        rst_n = 0;
        wait_clk(4);
        rst_n = 1;
        wait_clk(4);

        $display("=== I²C Master Test (CPU Architecture) ===");

        // I²C pins: ui_in[0]=SDA, ui_in[1]=SCL
        // Idle: SDA=1, SCL=1 (both released, pulled up)
        ui_in = 8'h03;  // 00000011: SDA=1, SCL=1
        wait_clk(2);

        // ============================================================
        // Firmware: I²C Master at ~100kHz using NCO timer for SCL
        // SCL is driven by Timer 0 NCO (via pin matrix PINSEL)
        // SDA is driven by CPU OUT instructions
        // ============================================================
        // Register allocation:
        // x4  = Timer index (0)
        // x5  = MODE_NCO_CLK (3)
        // x6  = SDA pin (0)
        // x7  = SCL pin (1)
        // x8  = Output direction (1) - NEEDED FOR DIR INSTRUCTION
        // x9  = Wait cycles (100) - ~1 SCL cycle at 100kHz = 500 CPU cycles @ 50MHz
        // x10 = Wait cycles (25) - quarter cycle
        // x11 = Constant 1 (for OUT=1/release)
        // x12 = Constant 0 (for OUT=0/drive low)
        // x13 = Pin select source for SCL (Timer 0 NCO = 1, needs to be in bits [7:4] = 0x10)
        // x14 = Tuning low byte (0xB8) / Slave address (0xA0)
        // x15 = Tuning high byte (0xFF80 with ADDI sign-ext, bit 8=1) / temp

        // ---- Program: Initialize NCO for ~100kHz ----
        // NCO increment = 0x80B8 (32952) for ~98kHz @ 50MHz
        // Write tuning: REG_TUNING_H = 0x80 (via ADDI 0x80 -> 0xFF80, bit 8=1), REG_TUNING = 0xB8
        // x4=0, x5=3
        spi_write(16'h0000, {INS_ADDI(4'h5, 8'h03), INS_ADDI(4'h4, 8'h00)});  // x4=timer0, x5=MODE=3
        spi_write(16'h0002, {INS_ADDI(4'h7, 8'h01), INS_ADDI(4'h6, 8'h00)});  // x6=SDA(0), x7=SCL(1)
        spi_write(16'h0004, {INS_ADDI(4'h9, 8'h64), INS_ADDI(4'h8, 8'h01)});  // x8=dir=1, x9=wait100
        spi_write(16'h0006, {INS_ADDI(4'hB, 8'h19), INS_ADDI(4'hA, 8'h19)});  // x10=wait25, x11=const1
        spi_write(16'h0008, {INS_TCFG(4'h4, 4'h5), INS_ADDI(4'hC, 8'h00)});   // x12=const0, TCFG timer0 MODE

        // ---- Write NCO tuning word to timer 0 ----
        // Write REG_TUNING (low byte) = 0xB8 using x14 (ORI for zero-extend, bit 8 = 0)
        spi_write(16'h000A, {INS_TUNING(4'h4, 4'hE), INS_ORI(4'hE, 8'hB8)});  // x14=0xB8, TUNING timer0 low
        // Write REG_TUNING_H (high byte) = 0x80 using x15 (ADDI for sign-ext, gives 0xFF80, bit 8 = 1)
        spi_write(16'h000C, {INS_TUNING(4'h4, 4'hF), INS_ADDI(4'hF, 8'h80)});  // x15=0xFF80 (bit 8=1), TUNING timer0 high

        // ---- Set up pin directions (open-drain outputs) ----
        spi_write(16'h000E, {INS_DIR(4'h6, 4'h8), INS_DIR(4'h7, 4'h8)});        // DIR SDA, DIR SCL (both output, x8=1)
        
        // ---- Pin select: SCL (pin 1) driven by Timer 0 NCO ----
        // PINSEL for pin 1 needs source in bits [7:4] = 0x10 (Timer 0 NCO)
        spi_write(16'h0010, {INS_PINSEL(4'h7, 4'hD), INS_ADDI(4'hD, 8'h10)});  // x13=0x10, PINSEL SCL, Timer0

        // ---- Slave address ----
        spi_write(16'h0012, {INS_ADDI(4'hF, 8'h08), INS_ADDI(4'hE, 8'hA0)});   // x14=0xA0 (slave addr), x15=8 (bit count)

        // ---- I²C idle: both lines high (released) ----
        // SCL is driven by NCO, SDA by CPU
        spi_write(16'h0014, {INS_OUT(4'h6, 4'hB), INS_NOP()});       // OUT SDA=1 (x11) - release
        spi_write(16'h0016, {INS_WAIT(4'hB, 4'h9), INS_WAIT(4'hB, 4'h9)});      // WAIT 100 cycles

        // ---- I²C START condition: SDA falls while SCL high ----
        spi_write(16'h0018, {INS_ADDI(4'hF, 8'h08), INS_OUT(4'h6, 4'hC)});     // OUT SDA=0 (x12), x15=8 (bit counter)
        spi_write(16'h001A, {INS_WAIT(4'hB, 4'hA), INS_WAIT(4'hB, 4'hA)});      // WAIT 25 cycles (quarter period)

        // ---- Send 8 bits (simplified: SDA=0 for all 8 SCL cycles) ----
        // 8 bits * 4 quarter-periods = 32 WAITs
        spi_write(16'h001C, {INS_WAIT(4'hB, 4'hA), INS_WAIT(4'hB, 4'hA)});
        spi_write(16'h001E, {INS_WAIT(4'hB, 4'hA), INS_WAIT(4'hB, 4'hA)});
        spi_write(16'h0020, {INS_WAIT(4'hB, 4'hA), INS_WAIT(4'hB, 4'hA)});
        spi_write(16'h0022, {INS_WAIT(4'hB, 4'hA), INS_WAIT(4'hB, 4'hA)});
        spi_write(16'h0024, {INS_WAIT(4'hB, 4'hA), INS_WAIT(4'hB, 4'hA)});
        spi_write(16'h0026, {INS_WAIT(4'hB, 4'hA), INS_WAIT(4'hB, 4'hA)});
        spi_write(16'h0028, {INS_WAIT(4'hB, 4'hA), INS_WAIT(4'hB, 4'hA)});
        spi_write(16'h002A, {INS_WAIT(4'hB, 4'hA), INS_WAIT(4'hB, 4'hA)});
        spi_write(16'h002C, {INS_WAIT(4'hB, 4'hA), INS_WAIT(4'hB, 4'hA)});
        spi_write(16'h002E, {INS_WAIT(4'hB, 4'hA), INS_WAIT(4'hB, 4'hA)});
        spi_write(16'h0030, {INS_WAIT(4'hB, 4'hA), INS_WAIT(4'hB, 4'hA)});
        spi_write(16'h0032, {INS_WAIT(4'hB, 4'hA), INS_WAIT(4'hB, 4'hA)});
        spi_write(16'h0034, {INS_WAIT(4'hB, 4'hA), INS_WAIT(4'hB, 4'hA)});
        spi_write(16'h0036, {INS_WAIT(4'hB, 4'hA), INS_WAIT(4'hB, 4'hA)});
        spi_write(16'h0038, {INS_WAIT(4'hB, 4'hA), INS_WAIT(4'hB, 4'hA)});
        spi_write(16'h003A, {INS_WAIT(4'hB, 4'hA), INS_WAIT(4'hB, 4'hA)});

        // ---- ACK bit: release SDA, read ACK ----
        spi_write(16'h003C, {INS_WAIT(4'hB, 4'hA), INS_OUT(4'h6, 4'hB)});       // OUT SDA=1 (release), WAIT
        spi_write(16'h003E, {INS_WAIT(4'hB, 4'hA), INS_NOP()});                  // WAIT

        // ---- I²C STOP condition: SDA rises while SCL high ----
        // Need to hold SCL high and raise SDA. But SCL is NCO-driven.
        // We can't easily stop NCO. Instead, just keep SDA high.
        spi_write(16'h0040, {INS_OUT(4'h6, 4'hC), INS_NOP()});                   // SDA=0
        spi_write(16'h0042, {INS_WAIT(4'hB, 4'hA), INS_WAIT(4'hB, 4'hA)});      // WAIT
        spi_write(16'h0044, {INS_OUT(4'h6, 4'hB), INS_NOP()});                   // SDA=1 (STOP)
        spi_write(16'h0046, {INS_WAIT(4'hB, 4'h9), INS_HALT()});                 // WAIT 100, HALT

        $display("Program loaded (37 instructions). Starting CPU...");
        spi_run(16'd74);  // 37 instruction pairs = 74 instructions

        wait_clk(50000);

        $display("=== CPU Registers ===");
        $display("R4 (timer): %h", dut.u_cpu.reg_debug[4]);
        $display("R5 (MODE): %h", dut.u_cpu.reg_debug[5]);
        $display("R6 (SDA pin): %h", dut.u_cpu.reg_debug[6]);
        $display("R7 (SCL pin): %h", dut.u_cpu.reg_debug[7]);
        $display("R8 (dir): %h", dut.u_cpu.reg_debug[8]);
        $display("R9 (wait100): %h", dut.u_cpu.reg_debug[9]);
        $display("R10 (wait25): %h", dut.u_cpu.reg_debug[10]);
        $display("R11 (const1): %h", dut.u_cpu.reg_debug[11]);
        $display("R12 (const0): %h", dut.u_cpu.reg_debug[12]);
        $display("R13 (sel src): %h", dut.u_cpu.reg_debug[13]);
        $display("R14 (slave addr): %h", dut.u_cpu.reg_debug[14]);
        $display("R15 (bit cnt): %h", dut.u_cpu.reg_debug[15]);
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
    initial begin #5000000; $display("TIMEOUT"); $finish; end

endmodule
