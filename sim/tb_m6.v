`timescale 1ns/1ps
module tb_m6;
    parameter CNT_W = 16;
    parameter FRAC = 1;
    parameter BIN_W = 8;
    parameter NUM_PINS = 8;
    localparam IDX_W = 4 + FRAC;

    reg clk = 0, rst_n = 0;
    reg [NUM_PINS-1:0] pins_in = 8'hFF;
    reg clear = 0, scan_start = 0, replay_start = 0;
    // Encoding layer inputs (channel 0 = SPI data line)
    reg [1:0] enc_mode_ch0 = 2'd0;
    reg [3:0] stuff_after_ch0 = 4'd0;

    wire [NUM_PINS*3-1:0] pin_roles;
    wire [NUM_PINS-1:0] role_valid;
    wire idle, scan_done;
    wire [IDX_W-1:0] peak_idx;
    wire [BIN_W-1:0] peak_count;
    wire result_valid, list_done, ambiguous;
    wire [3:0] result_proto, result_rank;
    wire [7:0] result_conf;
    wire replay_done, replay_error;
    wire [7:0] prog_len, seq_pc;

    integer errors = 0;

    m6_top #(.CNT_W(CNT_W), .FRAC(FRAC), .BIN_W(BIN_W), .NUM_PINS(NUM_PINS)) dut (
        .clk(clk), .rst_n(rst_n),
        .pins_in(pins_in),
        .clear(clear), .scan_start(scan_start), .replay_start(replay_start),
        .enc_mode_ch0(enc_mode_ch0), .stuff_after_ch0(stuff_after_ch0),
        .pin_roles(pin_roles), .role_valid(role_valid),
        .idle(idle), .peak_idx(peak_idx), .peak_count(peak_count), .scan_done(scan_done),
        .result_valid(result_valid), .result_proto(result_proto), .result_conf(result_conf),
        .result_rank(result_rank), .list_done(list_done), .ambiguous(ambiguous),
        .replay_done(replay_done), .replay_error(replay_error),
        .prog_len(prog_len), .seq_pc(seq_pc)
    );

    always #5 clk = ~clk;

    // Monitor key signals
    always @(posedge clk) begin
        if (scan_start) $display("  [TB] scan_start at t=%0t", $time);
        if (scan_done) $display("  [TB] scan_done at t=%0t", $time);
        if (list_done) $display("  [TB] list_done at t=%0t", $time);
        if (result_valid) $display("  [TB] result_valid: proto=%0d rank=%0d conf=%0d", result_proto, result_rank, result_conf);
        if (replay_done) $display("  [TB] replay_done at t=%0t", $time);
        if (replay_error) $display("  [TB] replay_error at t=%0t", $time);
    end

    task wait_clk(input integer n);
        integer j;
        begin for (j = 0; j < n; j = j + 1) @(negedge clk); end
    endtask

    task do_clear;
        begin @(negedge clk); clear = 1; @(negedge clk); clear = 0; end
    endtask

    task do_scan;
        begin 
            $display("  [TB] do_scan: asserting scan_start");
            @(negedge clk); scan_start = 1; @(negedge clk); scan_start = 0; 
            $display("  [TB] do_scan: waiting for scan_done...");
            wait (scan_done); 
            @(negedge clk); 
            $display("  [TB] scan_done received");
        end
    endtask

    // Simple SPI frame generator for testing
    task spi_send_frame(input [15:0] data, input integer bits, input integer half_period);
        integer i;
        begin
            pins_in[4] = 0; wait_clk(4);
            for (i = bits-1; i >= 0; i = i - 1) begin
                pins_in[1] = data[i];
                pins_in[0] = 0; wait_clk(half_period);
                pins_in[0] = 1; wait_clk(half_period);
            end
            pins_in[4] = 1; wait_clk(10);
        end
    endtask

    initial begin
        wait_clk(4); rst_n = 1; wait_clk(4);
        do_clear();

        $display("Test M6: Full discovery -> compile -> replay");

        // Generate some SPI traffic
        repeat (10) begin
            spi_send_frame(16'hA5, 8, 20);
            wait_clk(30);
        end

        // Wait for fingerprint matching to complete (list_done)
        // Just wait for a few list_done pulses
        wait_clk(100);

        do_scan();
        wait_clk(10);

        $display("Discovery complete. Top result: proto=%0d conf=%0d", result_proto, result_conf);
        $display("Program length: %0d", prog_len);

        // Start replay
        $display("Starting replay...");
        @(negedge clk); replay_start = 1; @(negedge clk); replay_start = 0;
        
        wait (replay_done || replay_error);
        @(negedge clk);
        
        if (replay_error) begin
            $display("  Replay ERROR");
            errors = errors + 1;
        end else begin
            $display("  Replay DONE (pc=%0d)", seq_pc);
        end

        if (errors == 0) $display("ALL TESTS PASSED");
        else $display("%0d TEST(S) FAILED", errors);
        $finish;
    end

    initial begin #50000000; $display("GLOBAL TIMEOUT"); $finish; end
endmodule
