module tb_emu_sync_jump;
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
    wire [2:0] seq_st = dut.u_sequencer.st;
    wire [15:0] reg0 = dut.u_sequencer.reg_file[0];
    wire [15:0] reg1 = dut.u_sequencer.reg_file[1];
    wire [7:0] pin_in_sync = dut.u_sequencer.pin_in_sync;
    wire [7:0] pin_in_prev = dut.u_sequencer.pin_in_prev;
    wire [15:0] wait_cnt = dut.u_sequencer.wait_cnt;
    wire [5:0] wait_mode = dut.u_sequencer.wait_mode;

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

    function [31:0] INS_LOAD(input [3:0] dst, input [15:0] val);
        begin INS_LOAD = {4'd9, dst, 8'd0, val}; end
    endfunction

    function [31:0] INS_DRIVE(input [3:0] mask, input [1:0] mode, input [1:0] reg_idx);
        begin INS_DRIVE = {4'd1, mask, mode, reg_idx, 20'd0}; end
    endfunction

    function [31:0] INS_WAIT(input [3:0] wait_mode, input [15:0] count);
        begin INS_WAIT = {4'd2, wait_mode, 12'd0, count}; end
    endfunction

    function [31:0] INS_SAMPLE(input [3:0] dst, input [3:0] mask);
        begin INS_SAMPLE = {4'd3, dst, mask, 20'd0}; end
    endfunction

    function [31:0] INS_SYNC(input [3:0] pin_mask, input [1:0] sync_mode, input [1:0] target_level, input [15:0] timeout);
        begin INS_SYNC = {4'd11, pin_mask, sync_mode, target_level, 4'd0, timeout}; end
    endfunction

    function [31:0] INS_JUMP(input [3:0] loop_reg, input [7:0] target, input [7:0] count);
        begin INS_JUMP = {4'd12, loop_reg, 8'd0, target, count}; end
    endfunction

    // Drive rising edges on pin 0 for SYNC test
    task drive_rising_edges(input integer num_edges);
        integer e;
        begin
            for (e = 0; e < num_edges; e = e + 1) begin
                wait_clk(10);
                $display("t=%0t: Setting pin 0 HIGH (rising edge #%0d)", $time, e+1);
                ui_in[0] = 1;
                wait_clk(10);
                $display("t=%0t: Setting pin 0 LOW (falling edge #%0d)", $time, e+1);
                ui_in[0] = 0;
            end
        end
    endtask

    initial begin
        rst_n = 0;
        wait_clk(4);
        rst_n = 1;
        wait_clk(4);

        $display("=== Protocol Emulator SYNC/JUMP Test ===");

        // Fixed program: LOAD R0=3 BEFORE the loop
        spi_write(8'h00, INS_LOAD(4'd0, 16'h0003));  // R0 = 3 (loop counter)
        spi_write(8'h01, INS_SYNC(4'h1, 2'b00, 2'b00, 16'd100));  // SYNC on pin 0 rise
        spi_write(8'h02, INS_SAMPLE(4'd1, 4'h1));  // Sample pin 0 -> R1
        spi_write(8'h03, INS_JUMP(4'd0, 8'd1, 8'd0));  // JUMP if R0>0 to PC=1
        spi_write(8'h04, INS_DRIVE(4'h2, 2'b01, 2'd0));  // Drive pin 1 high when done

        $display("Program loaded. Starting sequencer...");

        ui_in[0] = 0;
        spi_run(8'd5);

        wait_clk(50);
        
        // Drive 3 rising edges for 3 loop iterations
        drive_rising_edges(3);
        
        wait_clk(500);
        
        $display("=== Results ===");
        $display("Final PC: %d", seq_pc);
        $display("Done: %b, Error: %b", seq_done, seq_error);
        $display("R0 (counter): %h (expected 0000)", reg0);
        $display("R1 (sampled): %h (expected 0001)", reg1);

        if (reg0 == 16'h0000 && reg1 == 16'h0001) begin
            $display("PASS: SYNC and JUMP work correctly!");
        end else begin
            $display("FAIL: Unexpected register values");
        end

        $display("Test complete");
        $finish;
    end

    // Monitor SYNC state with pin values and wait_mode
    always @(posedge clk) begin
        if (seq_st == 4) begin // S_SYNC
            $display("t=%0t SYNC: pc=%d wait_cnt=%d wait_mode=%b pin_mask=%b sync_mode=%b pin_sync=%b pin_prev=%b rising=%b", 
                     $time, seq_pc, wait_cnt, wait_mode, wait_mode[3:0], wait_mode[5:4],
                     pin_in_sync, pin_in_prev, (pin_in_sync & ~pin_in_prev));
        end
    end

    initial begin #200000; $display("TIMEOUT"); $finish; end
endmodule
