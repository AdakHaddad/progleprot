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

    // Instruction encoding
    function [15:0] INS_ADDI(input [3:0] rd, input [7:0] imm);
        begin INS_ADDI = (4'h8 << 12) | (rd << 8) | imm; end
    endfunction

    function [15:0] INS_ORI(input [3:0] rd, input [7:0] imm);
        begin INS_ORI = (4'h9 << 12) | (rd << 8) | imm; end
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
    // Initial block: Load SPI Master firmware and start CPU
    // ============================================================
    initial begin
        rst_n = 0;
        wait_clk(4);
        rst_n = 1;
        wait_clk(4);

        $display("=== SPI Master Test (CPU Architecture) ===");

        wait_clk(2);

        // Register allocation:
        // x4  = Timer index (0)
        // x5  = MODE_NCO_CLK (3)
        // x6  = MOSI pin (0)
        // x7  = MISO pin (1) 
        // x8  = SCK pin (2)
        // x9  = CS pin (3)
        // x10 = Output direction (1)
        // x11 = Input direction (0)
        // x12 = Bit counter (8)
        // x13 = Wait cycles (1)
        // x14 = Constant 1
        // x15 = Constant 0 / Tuning high byte selector
        // xE  = Tuning low byte (0x00)
        // xF  = Tuning high byte (0x80 with bit 8=1 for REG_TUNING_H)
        // xD  = PINSEL source for SCK (0x01 = Timer 0 NCO, shifted by CPU)

        // ---- Program: Initialize NCO for 25MHz ----
        // NCO increment = 0x800000 (25MHz @ 50MHz = 1/2 clock)
        // Write tuning: REG_TUNING_H = 0x80 (via ADDI 0x80 -> 0xFF80, bit 8=1), REG_TUNING = 0x00
        spi_write(16'h0000, {INS_ADDI(4'h5, 8'h03), INS_ADDI(4'h4, 8'h00)});  // x4=timer0, x5=MODE=3
        spi_write(16'h0002, {INS_ADDI(4'h6, 8'h00), INS_ADDI(4'h7, 8'h01)});  // x6=MOSI(0), x7=MISO(1)
        spi_write(16'h0004, {INS_ADDI(4'h8, 8'h02), INS_ADDI(4'h9, 8'h03)});  // x8=SCK(2), x9=CS(3)
        spi_write(16'h0006, {INS_ADDI(4'hA, 8'h01), INS_ADDI(4'hB, 8'h00)});  // x10=dir=1, x11=dir=0
        spi_write(16'h0008, {INS_ADDI(4'hC, 8'h08), INS_ADDI(4'hD, 8'h01)});  // x12=8 bits, x13=wait1
        spi_write(16'h000A, {INS_ADDI(4'hE, 8'h00), INS_ADDI(4'hF, 8'h00)});  // x14=1, x15=0
        // PINSEL source for SCK (pin 2): needs source=1 (shifted by CPU to bits [11:8])
        spi_write(16'h000C, {INS_ADDI(4'hD, 8'h01), INS_NOP()});  // xD=0x01 (source=Timer0 NCO)

        // ---- Write NCO tuning word to timer 0 ----
        // Write REG_TUNING (low byte) = 0x00 using xE (ORI for zero-extend, bit 8 = 0)
        spi_write(16'h000E, {INS_TUNING(4'h4, 4'hE), INS_ORI(4'hE, 8'h00)});
        // Write REG_TUNING_H (high byte) = 0x80 using xF (ADDI for sign-ext, gives 0xFF80, bit 8 = 1)
        spi_write(16'h0010, {INS_TUNING(4'h4, 4'hF), INS_ADDI(4'hF, 8'h80)});

        // ---- Configure timer 0 NCO mode ----
        spi_write(16'h0012, {INS_TCFG(4'h4, 4'h5), INS_NOP()});   // TCFG timer0 MODE=3

        // ---- Set up pin directions (MOSI, SCK, CS = output; MISO = input) ----
        spi_write(16'h0014, {INS_DIR(4'h6, 4'hA), INS_DIR(4'h8, 4'hA)});  // DIR MOSI, DIR SCK
        spi_write(16'h0016, {INS_DIR(4'h9, 4'hA), INS_DIR(4'h7, 4'hB)});  // DIR CS, DIR MISO (input)
        
        // ---- Pin select: SCK (pin 2) driven by Timer 0 NCO (source=1 in bits [11:8]) ----
        spi_write(16'h0018, {INS_PINSEL(4'h8, 4'hD), INS_NOP()});  // PINSEL SCK, xD=0x01

        // ---- Initial state: CS high, MOSI low ----
        spi_write(16'h001A, {INS_OUT(4'h9, 4'hE), INS_OUT(4'h6, 4'hF)});  // CS=1, MOSI=0

        // ---- Send 8 bits: 0xA5 = 10100101 (MSB first) ----
        // Bit 7: 1
        spi_write(16'h001C, {INS_OUT(4'h9, 4'hF), INS_OUT(4'h6, 4'hE)});  // CS=0, MOSI=1
        spi_write(16'h001E, {INS_WAIT(4'h4, 4'hD), INS_WAIT(4'h4, 4'hD)}); // Wait 2 cycles (SCK rise+fall)
        
        // Bit 6: 0
        spi_write(16'h0020, {INS_OUT(4'h6, 4'hF), INS_WAIT(4'h4, 4'hD)});  // MOSI=0, wait
        spi_write(16'h0022, {INS_WAIT(4'h4, 4'hD), INS_WAIT(4'h4, 4'hD)}); // wait 2
        
        // Bit 5: 1
        spi_write(16'h0024, {INS_OUT(4'h6, 4'hE), INS_WAIT(4'h4, 4'hD)});  // MOSI=1, wait
        spi_write(16'h0026, {INS_WAIT(4'h4, 4'hD), INS_WAIT(4'h4, 4'hD)}); // wait 2
        
        // Bit 4: 0
        spi_write(16'h0028, {INS_OUT(4'h6, 4'hF), INS_WAIT(4'h4, 4'hD)});  // MOSI=0, wait
        spi_write(16'h002A, {INS_WAIT(4'h4, 4'hD), INS_WAIT(4'h4, 4'hD)}); // wait 2
        
        // Bit 3: 0
        spi_write(16'h002C, {INS_OUT(4'h6, 4'hF), INS_WAIT(4'h4, 4'hD)});  // MOSI=0, wait
        spi_write(16'h002E, {INS_WAIT(4'h4, 4'hD), INS_WAIT(4'h4, 4'hD)}); // wait 2
        
        // Bit 2: 1
        spi_write(16'h0030, {INS_OUT(4'h6, 4'hE), INS_WAIT(4'h4, 4'hD)});  // MOSI=1, wait
        spi_write(16'h0032, {INS_WAIT(4'h4, 4'hD), INS_WAIT(4'h4, 4'hD)}); // wait 2
        
        // Bit 1: 0
        spi_write(16'h0034, {INS_OUT(4'h6, 4'hF), INS_WAIT(4'h4, 4'hD)});  // MOSI=0, wait
        spi_write(16'h0036, {INS_WAIT(4'h4, 4'hD), INS_WAIT(4'h4, 4'hD)}); // wait 2
        
        // Bit 0: 1
        spi_write(16'h0038, {INS_OUT(4'h6, 4'hE), INS_WAIT(4'h4, 4'hD)});  // MOSI=1, wait
        spi_write(16'h003A, {INS_WAIT(4'h4, 4'hD), INS_WAIT(4'h4, 4'hD)}); // wait 2

        // ---- CS high (end transaction) ----
        spi_write(16'h003C, {INS_OUT(4'h9, 4'hE), INS_HALT()});  // CS=1, HALT

        $display("Program loaded (31 instructions). Starting CPU...");
        spi_run(16'd62);  // 31 instruction pairs = 62 instructions

        wait_clk(50000);

        $display("=== CPU Registers ===");
        $display("R4 (timer): %h", dut.u_cpu.reg_debug[4]);
        $display("R5 (MODE): %h", dut.u_cpu.reg_debug[5]);
        $display("R6 (MOSI): %h", dut.u_cpu.reg_debug[6]);
        $display("R7 (MISO): %h", dut.u_cpu.reg_debug[7]);
        $display("R8 (SCK): %h", dut.u_cpu.reg_debug[8]);
        $display("R9 (CS): %h", dut.u_cpu.reg_debug[9]);
        $display("R10 (dir_out): %h", dut.u_cpu.reg_debug[10]);
        $display("R11 (dir_in): %h", dut.u_cpu.reg_debug[11]);
        $display("R12 (bit cnt): %h", dut.u_cpu.reg_debug[12]);
        $display("R13 (wait): %h", dut.u_cpu.reg_debug[13]);
        $display("R14 (const1): %h", dut.u_cpu.reg_debug[14]);
        $display("R15 (const0/tuning): %h", dut.u_cpu.reg_debug[15]);
        $display("RD (pin_sel src): %h", dut.u_cpu.reg_debug[13]);
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
