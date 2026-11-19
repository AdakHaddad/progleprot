/*
 * Testbench for WAIT instruction
 */
module tb_emu_wait_test;

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

    // WAIT: OP_CUSTOM(0xF), funct=2, rs1=timer(0), rs2=cycles register
    // R1 = 5 (wait cycles), R2 = 0 (timer 0)
    // WAIT timer0, R1: 0xF221 (funct=2, rs1=2(R2=timer0), rs2=1(R1=cycles))

    localparam [15:0] INS_ADDI_x1_05  = 16'h8105;  // R1 = 5 (wait cycles)
    localparam [15:0] INS_ADDI_x2_00  = 16'h8200;  // R2 = 0 (timer 0)
    localparam [15:0] INS_WAIT_t0_x1  = 16'hF221;  // WAIT timer0, R1 (funct=2, rs1=2, rs2=1)
    localparam [15:0] INS_HALT        = 16'hFFFF;

    initial begin
        rst_n = 0;
        wait_clk(4);
        rst_n = 1;
        wait_clk(4);

        $display("=== WAIT Instruction Test ===");

        // Load program
        spi_write(16'h0000, {INS_ADDI_x2_00, INS_ADDI_x1_05});  // R1=5, R2=0
        spi_write(16'h0002, {INS_HALT, INS_WAIT_t0_x1});         // WAIT, HALT

        $display("Program loaded. Starting CPU...");
        spi_run(16'd8);  // 4 instructions * 2 bytes

        // Wait for CPU to complete (5 cycles + pipeline overhead)
        wait_clk(5000);

        $display("=== CPU Registers ===");
        $display("R0 (x0): %h", dut.u_cpu.reg_debug[0]);
        $display("R1 (x1): %h (wait cycles)", dut.u_cpu.reg_debug[1]);
        $display("R2 (x2): %h (timer)", dut.u_cpu.reg_debug[2]);
        $display("PC: %h", dut.u_cpu.pc_debug);

        if (dut.u_cpu.reg_debug[1] == 16'h0005 && dut.u_cpu.reg_debug[2] == 16'h0000) begin
            $display("PASS: WAIT instruction executed correctly!");
        end else begin
            $display("FAIL: Unexpected register values");
        end

        $display("=== Test Complete ===");
        $finish;
    end

    // Monitor pipeline state
    always @(posedge clk) begin
        if (dut.u_cpu.cpu_running) begin
            if (dut.u_cpu.pipe_st == 2'd4) begin // S_STALL
                $display("t=%0t STALL: ex_wait_cnt=%d, ex_is_wait=%b", 
                         $time, dut.u_cpu.ex_wait_cnt, dut.u_cpu.ex_is_wait);
            end
        end
    end

    initial begin #500000; $display("TIMEOUT"); $finish; end

endmodule
