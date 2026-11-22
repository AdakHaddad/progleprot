/* Back-to-back WAIT test with IHP SRAM */
module tb_wait_wait_ihp;

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

    // Program: ADDI x1, 5; WAIT x0, x1; WAIT x0, x1; HALT
    // Note: WAIT uses timer in rs1, cycles in rs2. x0 = 0 (timer 0)
    localparam [15:0] INS_ADDI_x1_05   = 16'h8105;
    localparam [15:0] INS_ADDI_x2_00   = 16'h8200;  // timer 0
    localparam [15:0] INS_WAIT_x2_x1   = 16'hF221;  // WAIT timer(x2=0), cycles(x1=5)
    localparam [15:0] INS_WAIT_x2_x1_2 = 16'hF221;  // Second WAIT
    localparam [15:0] INS_HALT         = 16'hFFFF;

    initial begin
        rst_n = 0;
        wait_clk(4);
        rst_n = 1;
        wait_clk(4);

        $display("=== Back-to-back WAIT Test (IHP SRAM) ===");

        spi_write(16'h0000, {INS_ADDI_x2_00, INS_ADDI_x1_05});
        spi_write(16'h0002, {INS_WAIT_x2_x1, INS_WAIT_x2_x1_2});
        spi_write(16'h0004, {INS_HALT,       16'h0000});

        spi_run(16'd12);

        wait_clk(1000);

        $display("=== CPU Registers ===");
        dbg_reg_idx = 4'd0; wait_clk(1); $display("R0: %h", dbg_reg_data);
        dbg_reg_idx = 4'd1; wait_clk(1); $display("R1: %h (should be 5)", dbg_reg_data);
        $display("PC: %h", dut.u_cpu.pc_debug);
        $display("cpu_running (internal): %b", dut.u_cpu.cpu_running);
        $display("cpu_done: %b", dut.cpu_done);

        $finish;
    end

    initial begin #100000; $display("TIMEOUT"); $finish; end

endmodule
