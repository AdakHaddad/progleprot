/*
 * Testbench for UART TX using CPU custom instructions
 * Tests OUT, DIR, WAIT instructions with timers
 */
module tb_emu_uart;

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
    // FUNCT_OUT=0x0: OUT pin, rs1 (pin in [7:4]), rs2 (value in register)
    // FUNCT_DIR=0x1: DIR pin, rs1 (pin in [7:4]), rs2 (direction in register LSB)
    // FUNCT_WAIT=0x2: WAIT timer, rs1 (timer in [7:4]), rs2 (cycles in register)
    // FUNCT_HALT=0xF: HALT

    // ADDI x1, 0x01  -> 0x8101  (R1 = 1 for pin value)
    // ADDI x2, 0x11  -> 0x8211  (R2 = 17 cycles ~ 3Mbps @ 50MHz)
    // ADDI x3, 0x00  -> 0x8300  (R3 = timer 0)
    // ADDI x4, 0x00  -> 0x8400  (R4 = pin 0)
    // ADDI x5, 0x01  -> 0x8501  (R5 = 1 for output direction)
    // ADDI x6, 0x00  -> 0x8600  (R6 = 0 for input direction)
    // ADDI x7, 0x01  -> 0x8701  (R7 = 1 for high)
    // ADDI x8, 0x00  -> 0x8800  (R8 = 0 for low)
    // ADDI x9, 0x0A  -> 0x890A  (R9 = 10 bits)
    
    // DIR pin0, R5 (output): funct=1, rs1=pin0, rs2=R5 -> 0xF105? No:
    // OP_CUSTOM=0xF, funct=DIR=0x1, rs1=pin number (4 bits), rs2=register
    // 0xF000 | (1<<8) | (pin<<4) | reg = 0xF100 | (0<<4) | 5 = 0xF105
    // WAIT timer0, R2: funct=2, rs1=timer0, rs2=R2 -> 0xF200 | (0<<4) | 2 = 0xF202
    // OUT pin0, R7: funct=0, rs1=pin0, rs2=R7 -> 0xF000 | (0<<8) | (0<<4) | 7 = 0xF007
    // OUT pin0, R8: funct=0, rs1=pin0, rs2=R8 -> 0xF000 | (0<<8) | (0<<4) | 8 = 0xF008

    localparam [15:0] INS_ADDI_x1_01  = 16'h8101;  // R1 = 1
    localparam [15:0] INS_ADDI_x2_11  = 16'h8211;  // R2 = 17 (bit period cycles)
    localparam [15:0] INS_ADDI_x3_00  = 16'h8300;  // R3 = timer 0
    localparam [15:0] INS_ADDI_x4_00  = 16'h8400;  // R4 = pin 0
    localparam [15:0] INS_ADDI_x5_01  = 16'h8501;  // R5 = 1 (output)
    localparam [15:0] INS_ADDI_x6_00  = 16'h8600;  // R6 = 0 (input)
    localparam [15:0] INS_ADDI_x7_01  = 16'h8701;  // R7 = 1 (high)
    localparam [15:0] INS_ADDI_x8_00  = 16'h8800;  // R8 = 0 (low)
    localparam [15:0] INS_ADDI_x9_0A  = 16'h890A;  // R9 = 10 (bit count)

    localparam [15:0] INS_DIR_pin0_x5 = 16'hF105;  // DIR pin0, R5 (output)
    localparam [15:0] INS_WAIT_t0_x2  = 16'hF202;  // WAIT timer0, R2
    localparam [15:0] INS_OUT_pin0_x7 = 16'hF007;  // OUT pin0, R7 (high)
    localparam [15:0] INS_OUT_pin0_x8 = 16'hF008;  // OUT pin0, R8 (low)
    localparam [15:0] INS_HALT        = 16'hFFFF;  // HALT

    initial begin
        rst_n = 0;
        wait_clk(4);
        rst_n = 1;
        wait_clk(4);

        $display("=== emu_top UART TX Test ===");

        // Load program: 11 instructions
        // PC=0:  ADDI x1, 1
        // PC=2:  ADDI x2, 17
        // PC=4:  ADDI x3, 0
        // PC=6:  ADDI x4, 0
        // PC=8:  ADDI x5, 1
        // PC=10: ADDI x6, 0
        // PC=12: ADDI x7, 1
        // PC=14: ADDI x8, 0
        // PC=16: ADDI x9, 10
        // PC=18: DIR pin0, x5
        // PC=20: WAIT timer0, x2
        // PC=22: OUT pin0, x7 (start bit=0? Actually high=1, low=0)
        // PC=24: OUT pin0, x8 (low)
        // PC=26: WAIT timer0, x2
        // PC=28: OUT pin0, x7 (high)
        // PC=30: WAIT timer0, x2
        // PC=32: HALT

        // Send 0x55 = 01010101 (start=0, data=01010101, stop=1)
        // For simplicity, just test one cycle
        
        spi_write(16'h0000, {INS_ADDI_x2_11, INS_ADDI_x1_01});   // addr 0,1
        spi_write(16'h0002, {INS_ADDI_x4_00, INS_ADDI_x3_00});   // addr 2,3
        spi_write(16'h0004, {INS_ADDI_x6_00, INS_ADDI_x5_01});   // addr 4,5
        spi_write(16'h0006, {INS_ADDI_x8_00, INS_ADDI_x7_01});   // addr 6,7
        spi_write(16'h0008, {INS_DIR_pin0_x5, INS_ADDI_x9_0A});  // addr 8,9
        spi_write(16'h000A, {INS_OUT_pin0_x8, INS_WAIT_t0_x2});  // addr 10,11 (start bit 0, wait)
        spi_write(16'h000C, {INS_OUT_pin0_x7, INS_WAIT_t0_x2});  // addr 12,13 (data bit 1, wait)
        spi_write(16'h000E, {INS_OUT_pin0_x8, INS_WAIT_t0_x2});  // addr 14,15 (data bit 0, wait)
        spi_write(16'h0010, {INS_OUT_pin0_x7, INS_WAIT_t0_x2});  // addr 16,17 (data bit 1, wait)
        spi_write(16'h0012, {INS_OUT_pin0_x8, INS_WAIT_t0_x2});  // addr 18,19 (data bit 0, wait)
        spi_write(16'h0014, {INS_OUT_pin0_x7, INS_WAIT_t0_x2});  // addr 20,21 (data bit 1, wait)
        spi_write(16'h0016, {INS_OUT_pin0_x8, INS_WAIT_t0_x2});  // addr 22,23 (data bit 0, wait)
        spi_write(16'h0018, {INS_OUT_pin0_x7, INS_WAIT_t0_x2});  // addr 24,25 (data bit 1, wait)
        spi_write(16'h001A, {INS_OUT_pin0_x7, INS_HALT});        // addr 26,27 (stop bit 1, halt)

        $display("Program loaded (14 instructions = 28 bytes). Starting CPU...");
        spi_run(16'd28);

        // Wait for CPU to complete
        wait_clk(200000);

        $display("=== CPU Registers ===");
        $display("R0 (x0): %h (hardwired 0)", dut.u_cpu.reg_debug[0]);
        $display("R1 (x1): %h", dut.u_cpu.reg_debug[1]);
        $display("R2 (x2): %h (cycles)", dut.u_cpu.reg_debug[2]);
        $display("R3 (x3): %h (timer)", dut.u_cpu.reg_debug[3]);
        $display("R4 (x4): %h (pin)", dut.u_cpu.reg_debug[4]);
        $display("R5 (x5): %h (dir=out)", dut.u_cpu.reg_debug[5]);
        $display("R7 (x7): %h (val=1)", dut.u_cpu.reg_debug[7]);
        $display("R8 (x8): %h (val=0)", dut.u_cpu.reg_debug[8]);
        $display("PC: %h", dut.u_cpu.pc_debug);
        $display("Pin 0 out: %b, Pin 0 OE: %b", uo_out[0], uio_oe[0]);

        $display("=== Test Complete ===");
        $finish;
    end

    // Monitor TX pin
    always @(posedge clk) begin
        if (dut.u_cpu.cpu_running && uio_oe[0]) begin
            $display("t=%0t TX pin 0: %b (PC=%h)", $time, uo_out[0], dut.u_cpu.pc_debug);
        end
    end

    initial begin #5000000; $display("TIMEOUT"); $finish; end

endmodule
