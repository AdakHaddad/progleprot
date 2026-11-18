/*
 * Testbench for UART TX using CPU custom instructions with NCO timer
 * Tests OUT, DIR, WAIT, TCFG instructions with NCO timer for 3Mbps
 */
module tb_emu_uart_nco;

    reg clk = 0;
    reg rst_n = 0;
    reg [7:0] ui_in = 8'h00;
    reg [7:0] uio_in = 8'hFF;  // SPI idle: SCK=1, MOSI=1, CS_N=1
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

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
        .cpu_error(uio_out[2])
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

    // CPU ISA instruction encoding (16-bit)
    // OP_ALU (0x0): [15:12]=0, [11:8]=rd, [7:4]=rs1, [3:0]=rs2
    // OP_IMM (0x8): [15:12]=8, [11:8]=rd, [7:0]=imm8 (sign-extended)
    // OP_CUSTOM (0xF): [15:12]=F, [11:8]=funct, [7:4]=rs1, [3:0]=rs2/rd

    // FUNCT codes:
    // FUNCT_OUT=0x0: OUT pin, rs1 (pin in [7:4]), rs2 (value in register LSB)
    // FUNCT_DIR=0x1: DIR pin, rs1 (pin in [7:4]), rs2 (direction in register LSB)
    // FUNCT_WAIT=0x2: WAIT timer, rs1 (timer in [7:4]), rs2 (cycles in register)
    // FUNCT_TCFG=0x5: TCFG timer, rs1 (timer in [7:4]), rs2 (config in register)
    // FUNCT_HALT=0xF: HALT

    // Registers:
    // R1 = 1 (high value)
    // R2 = 0 (low value)
    // R3 = timer 0 index
    // R4 = pin 0 index
    // R5 = 1 (output direction)
    // R6 = NCO config: MODE_NCO_CLK=3
    // R7 = 10 (bit counter)
    // R8 = NCO tuning word low (0x29)
    // R9 = NCO tuning word high (0x5C29 -> mid=0x5C, high=0x0F)
    // R10 = NCO tuning word mid
    // R11 = NCO tuning word high

    localparam [15:0] INS_ADDI_x1_01  = 16'h8101;  // R1 = 1
    localparam [15:0] INS_ADDI_x2_00  = 16'h8200;  // R2 = 0
    localparam [15:0] INS_ADDI_x3_00  = 16'h8300;  // R3 = timer 0
    localparam [15:0] INS_ADDI_x4_00  = 16'h8400;  // R4 = pin 0
    localparam [15:0] INS_ADDI_x5_01  = 16'h8501;  // R5 = 1 (output)
    localparam [15:0] INS_ADDI_x6_03  = 16'h8603;  // R6 = 3 (MODE_NCO_CLK)
    localparam [15:0] INS_ADDI_x7_0A  = 16'h870A;  // R7 = 10 (bit count)
    localparam [15:0] INS_ADDI_x8_29  = 16'h8829;  // R8 = 0x29 (NCO low)
    localparam [15:0] INS_ADDI_x9_0F  = 16'h890F;  // R9 = 0x0F (NCO high)
    localparam [15:0] INS_ADDI_x10_5C = 16'h8A5C;  // R10 = 0x5C (NCO mid)

    localparam [15:0] INS_DIR_pin0_x5 = 16'hF105;  // DIR pin0, R5 (output)
    localparam [15:0] INS_TCFG_t0_x6  = 16'hF506;  // TCFG timer0, R6 (NCO mode)
    localparam [15:0] INS_WAIT_t0_x7  = 16'hF207;  // WAIT timer0, R7 (10 cycles = NCO toggle count)
    localparam [15:0] INS_OUT_pin0_x1 = 16'hF001;  // OUT pin0, R1 (high)
    localparam [15:0] INS_OUT_pin0_x2 = 16'hF002;  // OUT pin0, R2 (low)
    localparam [15:0] INS_HALT        = 16'hFFFF;  // HALT

    // Program:
    // 0:  ADDI x1, 1        ; R1=1
    // 2:  ADDI x2, 0        ; R2=0
    // 4:  ADDI x3, 0        ; R3=timer0
    // 6:  ADDI x4, 0        ; R4=pin0
    // 8:  ADDI x5, 1        ; R5=output
    // 10: ADDI x6, 3        ; R6=MODE_NCO_CLK
    // 12: ADDI x7, 10       ; R7=bit_count
    // 14: ADDI x8, 0x29     ; R8=NCO low
    // 16: ADDI x9, 0x0F     ; R9=NCO high (but need mid=0x5C)
    // 18: ADDI x10, 0x5C    ; R10=NCO mid
    // 20: DIR pin0, x5      ; pin0 output
    // 22: TCFG timer0, x6   ; timer0 NCO mode
    // 24: OUT pin0, x2      ; start bit=0
    // 26: WAIT timer0, x7   ; wait 10 NCO cycles
    // 28: OUT pin0, x1      ; data bit 1
    // 30: WAIT timer0, x7
    // 32: OUT pin0, x2      ; data bit 0
    // 34: WAIT timer0, x7
    // 36: OUT pin0, x1      ; data bit 1
    // 38: WAIT timer0, x7
    // 40: OUT pin0, x2      ; data bit 0
    // 42: WAIT timer0, x7
    // 44: OUT pin0, x1      ; data bit 1
    // 46: WAIT timer0, x7
    // 48: OUT pin0, x2      ; data bit 0
    // 50: WAIT timer0, x7
    // 52: OUT pin0, x1      ; data bit 1
    // 54: WAIT timer0, x7
    // 56: OUT pin0, x1      ; stop bit=1
    // 58: HALT

    initial begin
        rst_n = 0;
        wait_clk(4);
        rst_n = 1;
        wait_clk(4);

        $display("=== emu_top UART TX with NCO Test ===");

        // Load program (30 instructions = 60 bytes)
        spi_write(16'h0000, {INS_ADDI_x2_00, INS_ADDI_x1_01});   // addr 0,1
        spi_write(16'h0002, {INS_ADDI_x4_00, INS_ADDI_x3_00});   // addr 2,3
        spi_write(16'h0004, {INS_ADDI_x6_03, INS_ADDI_x5_01});   // addr 4,5
        spi_write(16'h0006, {INS_ADDI_x8_29, INS_ADDI_x7_0A});   // addr 6,7
        spi_write(16'h0008, {INS_ADDI_x10_5C, INS_ADDI_x9_0F});  // addr 8,9
        spi_write(16'h000A, {INS_TCFG_t0_x6, INS_DIR_pin0_x5});  // addr 10,11
        spi_write(16'h000C, {INS_WAIT_t0_x7, INS_OUT_pin0_x2});  // addr 12,13 (start bit 0)
        spi_write(16'h000E, {INS_OUT_pin0_x1, INS_WAIT_t0_x7});  // addr 14,15 (bit 1)
        spi_write(16'h0010, {INS_WAIT_t0_x7, INS_OUT_pin0_x2});  // addr 16,17 (bit 0)
        spi_write(16'h0012, {INS_OUT_pin0_x1, INS_WAIT_t0_x7});  // addr 18,19 (bit 1)
        spi_write(16'h0014, {INS_WAIT_t0_x7, INS_OUT_pin0_x2});  // addr 20,21 (bit 0)
        spi_write(16'h0016, {INS_OUT_pin0_x1, INS_WAIT_t0_x7});  // addr 22,23 (bit 1)
        spi_write(16'h0018, {INS_WAIT_t0_x7, INS_OUT_pin0_x2});  // addr 24,25 (bit 0)
        spi_write(16'h001A, {INS_OUT_pin0_x1, INS_WAIT_t0_x7});  // addr 26,27 (bit 1)
        spi_write(16'h001C, {INS_OUT_pin0_x1, INS_HALT});        // addr 28,29 (stop bit 1, halt)

        $display("Program loaded (30 instructions = 60 bytes). Starting CPU...");
        spi_run(16'd60);

        // Wait for CPU to complete
        wait_clk(500000);

        $display("=== CPU Registers ===");
        $display("R0 (x0): %h (hardwired 0)", dut.u_cpu.reg_debug[0]);
        $display("R1 (x1): %h (val=1)", dut.u_cpu.reg_debug[1]);
        $display("R2 (x2): %h (val=0)", dut.u_cpu.reg_debug[2]);
        $display("R3 (x3): %h (timer=0)", dut.u_cpu.reg_debug[3]);
        $display("R4 (x4): %h (pin=0)", dut.u_cpu.reg_debug[4]);
        $display("R5 (x5): %h (dir=out)", dut.u_cpu.reg_debug[5]);
        $display("R6 (x6): %h (mode=3)", dut.u_cpu.reg_debug[6]);
        $display("R7 (x7): %h (bits=10)", dut.u_cpu.reg_debug[7]);
        $display("R8 (x8): %h (NCO low=0x29)", dut.u_cpu.reg_debug[8]);
        $display("R9 (x9): %h (NCO high=0x0F)", dut.u_cpu.reg_debug[9]);
        $display("R10 (x10): %h (NCO mid=0x5C)", dut.u_cpu.reg_debug[10]);
        $display("PC: %h", dut.u_cpu.pc_debug);
        $display("Pin 0 out: %b, Pin 0 OE: %b", uo_out[0], uio_oe[0]);

        $display("=== Test Complete ===");
        $finish;
    end

    // Monitor TX pin
    integer tx_count;
    initial tx_count = 0;
    always @(posedge clk) begin
        if (dut.u_cpu.cpu_running && uio_oe[0] && tx_count < 100) begin
            $display("t=%0t TX pin 0: %b (PC=%h)", $time, uo_out[0], dut.u_cpu.pc_debug);
            tx_count = tx_count + 1;
        end
    end

    initial begin #5000000; $display("TIMEOUT"); $finish; end

endmodule
