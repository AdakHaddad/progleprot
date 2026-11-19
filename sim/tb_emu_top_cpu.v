/*
 * Testbench for emu_top CPU architecture
 * Tests CPU + Timer + Pin Matrix integration via SPI host interface
 */
module tb_emu_top_cpu;

    reg clk = 0;
    reg rst_n = 0;
    reg [7:0] ui_in = 8'h00;
    reg [7:0] uio_in = 8'hFF;  // SPI idle: SCK=1, MOSI=1, CS_N=1
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    // Instantiate the new CPU-based top module
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

    // ADDI x1, 0x10: opcode=8, rd=1, imm8=0x10 -> 0x8110
    // ADDI x2, 0x20: opcode=8, rd=2, imm8=0x20 -> 0x8220
    // ADD x3, x1, x2: opcode=0, rd=3, rs1=1, rs2=2 -> 0x0312
    // OUT pin0, x3: opcode=F, funct=0 (OUT), rs1=3 (pin=0 in low 4, val in high?), rd=0 -> 0xF030? 
    //   Actually OUT: pin in rs1[3:0], value from rs1[15:4] or rs2? Let's use: pin=rs1[3:0], value=rs2
    //   For OUT pin0, x3: funct=0, rs1=0 (pin 0), rs2=3 (value from x3) -> 0xF003
    // SWAP: funct=8 -> 0xF800
    // HALT: funct=F -> 0xFFFF

    localparam [15:0] INS_ADDI_x1_10 = 16'h8110;    // ADDI x1, 0x10 (R1 = 16)
    localparam [15:0] INS_ADDI_x2_20 = 16'h8220;    // ADDI x2, 0x20 (R2 = 32)
    localparam [15:0] INS_ADD_x3_x1_x2 = 16'h0312;  // ADD x3, x1, x2 (R3 = R1 + R2 = 48)
    localparam [15:0] INS_OUT_pin0_x3 = 16'hF003;   // OUT pin0, x3 (funct=0, rs1=pin0, rs2=x3)
    localparam [15:0] INS_SWAP = 16'hF800;          // SWAP (funct=8)
    localparam [15:0] INS_HALT = 16'hFFFF;          // HALT (opcode=F, funct=F)

    // host_if splits 32-bit data: low 16 bits -> addr, high 16 bits -> addr+1
    // CPU PC: 0,2,4,6... maps to prog_ram[PC/2]
    // To get instructions at PC=0,2,4,6,8,10,12:
    // prog_ram[0]=8110, [1]=8220, [2]=0312, [3]=F003, [4]=F800, [5]=FFFF

    initial begin
        rst_n = 0;
        wait_clk(4);
        rst_n = 1;
        wait_clk(4);

        $display("=== emu_top CPU Architecture Test ===");

        // Load program: 6 instructions at PC = 0, 2, 4, 6, 8, 10
        // prog_ram[0]=8110, [1]=8220, [2]=0312, [3]=F003, [4]=F800, [5]=FFFF
        spi_write(16'h0000, {INS_ADDI_x2_20, INS_ADDI_x1_10});   // addr 0: 8110, addr 1: 8220
        spi_write(16'h0002, {INS_OUT_pin0_x3, INS_ADD_x3_x1_x2}); // addr 2: 0312, addr 3: F003
        spi_write(16'h0004, {INS_HALT, INS_SWAP});               // addr 4: F800, addr 5: FFFF

        $display("Program loaded (6 instructions). Starting CPU...");
        spi_run(16'd12);  // Program length in bytes (6 instructions * 2 bytes)

        // Wait for CPU to complete
        wait_clk(50000);

        $display("=== CPU Registers ===");
        $display("R0 (x0): %h (hardwired 0)", dut.u_cpu.reg_debug[0]);
        $display("R1 (x1): %h (expected 0010 = 16)", dut.u_cpu.reg_debug[1]);
        $display("R2 (x2): %h (expected 0020 = 32)", dut.u_cpu.reg_debug[2]);
        $display("R3 (x3): %h (expected 0030 = 48)", dut.u_cpu.reg_debug[3]);
        $display("PC: %h", dut.u_cpu.pc_debug);
        $display("CPU Done: %b, CPU Running: %b", dut.cpu_error, dut.cpu_running);
        $display("Pin 0 out: %b, Pin 0 OE: %b", uo_out[0], uio_oe[0]);

        if (dut.u_cpu.reg_debug[1] == 16'h0010 && 
            dut.u_cpu.reg_debug[2] == 16'h0020 && 
            dut.u_cpu.reg_debug[3] == 16'h0030) begin
            $display("PASS: CPU executed correctly!");
        end else begin
            $display("FAIL: Unexpected register values");
        end

        $display("=== Test Complete ===");
        $finish;
    end

    // Monitor CPU state
    always @(posedge clk) begin
        if (dut.u_cpu.cpu_running) begin
            if (dut.u_cpu.pipe_st == 2'd3) begin // S_WB
                $display("t=%0t WB: pc=%h, rd=%d, wb_reg_write=%b, wb_data=%h, wb_is_halt=%b", 
                         $time, dut.u_cpu.ex_pc, dut.u_cpu.wb_rd, dut.u_cpu.wb_reg_write, 
                         dut.u_cpu.wb_data, dut.u_cpu.wb_is_halt);
            end
            if (dut.u_cpu.pipe_st == 2'd0) begin // S_IF
                $display("t=%0t IF: pc=%h, instr=%h", $time, dut.u_cpu.pc_debug, dut.u_cpu.if_instr);
            end
        end
    end

    initial begin #2000000; $display("TIMEOUT"); $finish; end

endmodule
