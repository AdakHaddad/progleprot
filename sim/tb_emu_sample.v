module tb_emu_sample;
    reg clk = 0, rst_n = 0, ena = 1;
    reg [7:0] ui_in = 0;
    reg [7:0] uio_in = 8'hFF;
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    tt_um_protocol_emu dut (
        .ui_in(ui_in), .uo_out(uo_out), .uio_in(uio_in), .uio_out(uio_out), .uio_oe(uio_oe),
        .ena(ena), .clk(clk), .rst_n(rst_n)
    );

    always #10 clk = ~clk;

    wire [7:0] pin_out = dut.pin_out;
    wire [7:0] pin_oe  = dut.pin_oe;
    wire [7:0] seq_pc  = dut.seq_pc;
    wire       seq_done = dut.seq_done;
    wire       seq_error = dut.seq_error;
    wire       seq_start = dut.u_sequencer.start;
    wire [7:0] prog_len = dut.u_sequencer.prog_len;
    wire       prog_valid = dut.u_sequencer.prog_valid;
    wire [1:0] seq_st = dut.u_sequencer.st;
    wire [15:0] reg0 = dut.u_sequencer.reg_file[0];
    wire [15:0] reg1 = dut.u_sequencer.reg_file[1];
    wire [15:0] reg2 = dut.u_sequencer.reg_file[2];
    wire [15:0] reg3 = dut.u_sequencer.reg_file[3];

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
            $display("spi_write: addr=%h data=%h (OP=%h dst_reg=%h pin_mask=%h)", 
                     addr, data, data[31:28], data[27:24], data[23:20]);
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
            $display("spi_run: length=%h", length);
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

    // Instruction encoding matching pdis_sequencer:
    // OP_LOAD = 4'd9
    // [31:28] = OP (4 bits) - OP_LOAD=9
    // [27:24] = dst_reg (4 bits)
    // [23:16] = unused (8 bits)
    // [15:0]  = immediate value (16 bits)
    function [31:0] INS_LOAD(input [3:0] dst_reg, input [15:0] val);
        begin INS_LOAD = {4'd9, dst_reg, 8'd0, val}; end
    endfunction

    // OP_SAMPLE = 4'd3
    // [31:28] = OP (4 bits) - OP_SAMPLE=3
    // [27:24] = dst_reg (4 bits)
    // [23:20] = pin_mask (4 bits) - only covers pins 0-3
    // [19:0]  = unused
    function [31:0] INS_SAMPLE(input [3:0] dst_reg, input [3:0] pin_mask);
        begin INS_SAMPLE = {4'd3, dst_reg, pin_mask, 20'd0}; end
    endfunction

    // OP_DRIVE = 4'd1
    function [31:0] INS_DRIVE(input [3:0] mask, input [1:0] mode, input [1:0] reg_idx);
        begin INS_DRIVE = {4'd1, mask, mode, reg_idx, 20'd0}; end
    endfunction

    // OP_WAIT = 4'd2
    function [31:0] INS_WAIT(input [3:0] wait_mode, input [15:0] count);
        begin INS_WAIT = {4'd2, wait_mode, 12'd0, count}; end
    endfunction

    initial begin
        rst_n = 0;
        wait_clk(4);
        rst_n = 1;
        wait_clk(4);

        $display("=== Protocol Emulator SAMPLE Test ===");

        // Test 1: Sample pin 0 (high) into reg 0
        spi_write(8'h00, INS_LOAD(4'd0, 16'h0000));  // Clear reg 0
        spi_write(8'h01, INS_SAMPLE(4'd0, 4'h1));    // Sample pin 0 -> reg 0

        // Test 2: Sample pin 1 (low) into reg 1
        spi_write(8'h02, INS_LOAD(4'd1, 16'h0000));  // Clear reg 1
        spi_write(8'h03, INS_SAMPLE(4'd1, 4'h2));    // Sample pin 1 -> reg 1

        // Test 3: Sample pins 2-3 (both high) into reg 2
        spi_write(8'h04, INS_LOAD(4'd2, 16'h0000));  // Clear reg 2
        spi_write(8'h05, INS_SAMPLE(4'd2, 4'hC));    // Sample pins 2,3 -> reg 2

        // Test 4: Sample pin 3 (high) into reg 3
        spi_write(8'h06, INS_LOAD(4'd3, 16'h0000));  // Clear reg 3
        spi_write(8'h07, INS_SAMPLE(4'd3, 4'h8));    // Sample pin 3 -> reg 3

        $display("Program loaded. Starting sequencer...");

        // Set up pin inputs: pins 0,2,3 high; pin 1 low
        ui_in = 8'b11111101;  // pin 0=1, pin 1=0, pin 2=1, pin 3=1, pin 4-7=1

        spi_run(8'd8);

        // Wait for sequencer to complete
        wait_clk(100);
        
        $display("=== Results ===");
        $display("reg0 (pin 0): %h (expected 0001)", reg0);
        $display("reg1 (pin 1): %h (expected 0000)", reg1);
        $display("reg2 (pins 2-3): %h (expected 000C)", reg2);
        $display("reg3 (pin 3): %h (expected 0008)", reg3);

        if (reg0 == 16'h0001 && reg1 == 16'h0000 && reg2 == 16'h000C && reg3 == 16'h0008) begin
            $display("PASS: SAMPLE instruction works correctly!");
        end else begin
            $display("FAIL: SAMPLE instruction mismatch!");
        end

        $display("Test complete");
        $finish;
    end

    // Monitor pin sampling
    always @(posedge clk) begin
        if (seq_st == 2) begin // S_EXECUTE
            $display("t=%0t EXEC: pc=%d instr=%h reg0=%h reg1=%h reg2=%h reg3=%h", 
                     $time, seq_pc, dut.u_sequencer.instr, reg0, reg1, reg2, reg3);
        end
    end

    initial begin #50000; $display("TIMEOUT"); $finish; end
endmodule
