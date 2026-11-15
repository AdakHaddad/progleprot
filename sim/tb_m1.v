`timescale 1ns/1ps
module tb_m1;
    parameter FRAC = 1;
    parameter BIN_W = 8;
    localparam IDX_W = 4 + FRAC;
    reg clk = 0, rst_n = 0;
    reg sig = 1;
    reg clear = 0, scan_start = 0;
    wire idle, scan_done;
    wire [IDX_W-1:0]  peak_idx;
    wire [BIN_W-1:0] peak_count;
    integer errors = 0;
    reg [IDX_W-1:0] exp_a, exp_b, exp_c;
    integer idle_seen = 0;

    m1_top #(.FRAC(FRAC), .BIN_W(BIN_W)) dut (.clk(clk), .rst_n(rst_n), .signal_in(sig), .clear(clear),
                .scan_start(scan_start), .idle(idle),
                .peak_idx(peak_idx), .peak_count(peak_count), .scan_done(scan_done));

    always #5 clk = ~clk;
    always @(posedge clk) if (idle) idle_seen = idle_seen + 1;

    // ---------- unit check: log_bucket ----------
    reg  [15:0] lb_x;
    wire [IDX_W-1:0]  lb_idx;
    log_bucket #(.W(16), .FRAC(FRAC)) u_lb_chk (.x(lb_x), .idx(lb_idx));

    task check_bucket(input [15:0] x, input [IDX_W-1:0] expect_idx);
        begin
            lb_x = x; #1;
            if (lb_idx !== expect_idx) begin
                $display("FAIL log_bucket(%0d) = %0d, expected %0d", x, lb_idx, expect_idx);
                errors = errors + 1;
            end
        end
    endtask

    integer k;
    reg [IDX_W-1:0] last_idx;
    task check_monotonic;
        begin
            last_idx = 0;
            for (k = 1; k < 65536; k = k + 1) begin
                lb_x = k[15:0]; #1;
                if (lb_idx < last_idx) begin
                    $display("FAIL log_bucket not monotonic at %0d", k);
                    errors = errors + 1;
                end
                last_idx = lb_idx;
            end
        end
    endtask

    // ---------- helpers ----------
    task wait_clk(input integer n);
        integer j;
        begin for (j = 0; j < n; j = j + 1) @(negedge clk); end
    endtask

    task send_uart_byte(input [7:0] b, input integer cpb);
        integer bi;
        begin
            sig = 0; wait_clk(cpb);                   // start
            for (bi = 0; bi < 8; bi = bi + 1) begin   // LSB first
                sig = b[bi]; wait_clk(cpb);
            end
            sig = 1; wait_clk(cpb);                   // stop
        end
    endtask

    task do_scan;
        begin
            @(negedge clk); scan_start = 1; @(negedge clk); scan_start = 0;
            wait (scan_done); @(negedge clk);
        end
    endtask

    task do_clear;
        begin @(negedge clk); clear = 1; @(negedge clk); clear = 0; end
    endtask

    // ---------- edge_interval direct check (via top-level histogram) ----------
    // Known intervals 10, 10, 10, 25, 10, 10 -> bucket(10)=13 count 5? edges: see below.
    integer n;
    reg [7:0] rnd;

    initial begin
        // log_bucket spot checks
        if (FRAC == 2) begin
            check_bucket(16'd0, 0);  check_bucket(16'd1, 0);  check_bucket(16'd2, 4);
            check_bucket(16'd4, 8);  check_bucket(16'd5, 9);  check_bucket(16'd20, 17);
            check_bucket(16'd33, 20); check_bucket(16'd100, 26); check_bucket(16'd65535, 63);
        end else if (FRAC == 1) begin
            check_bucket(16'd0, 0);  check_bucket(16'd2, 2);  check_bucket(16'd3, 3);
            check_bucket(16'd20, 8); check_bucket(16'd33, 10); check_bucket(16'd100, 13);
            check_bucket(16'd65535, 31);
        end
        lb_x = 16'd20;  #1; exp_a = lb_idx;
        lb_x = 16'd100; #1; exp_b = lb_idx;
        lb_x = 16'd33;  #1; exp_c = lb_idx;
        check_monotonic;

        // reset
        wait_clk(4); rst_n = 1; wait_clk(4);

        // Test A: square wave, half period 20 cycles (SPI-like clock) -> bucket 17
        do_clear;
        for (n = 0; n < 60; n = n + 1) begin sig = ~sig; wait_clk(20); end
        do_scan;
        if (peak_idx !== exp_a || peak_count < 50) begin
            $display("FAIL A: peak_idx=%0d count=%0d (expected %0d, >=50)", peak_idx, peak_count, exp_a);
            errors = errors + 1;
        end else $display("PASS A: 20-cycle clock -> bucket %0d, count %0d", peak_idx, peak_count);

        // Test B: UART 8N1 at 100 cycles/bit, random bytes -> bucket 26
        do_clear; sig = 1; wait_clk(300);
        for (n = 0; n < 40; n = n + 1) begin
            rnd = $random;
            send_uart_byte(rnd, 100);
        end
        send_uart_byte(8'h55, 100); send_uart_byte(8'h55, 100);
        do_scan;
        if (peak_idx !== exp_b) begin
            $display("FAIL B: peak_idx=%0d count=%0d (expected %0d)", peak_idx, peak_count, exp_b);
            errors = errors + 1;
        end else $display("PASS B: UART 100 cyc/bit -> bucket %0d, count %0d", peak_idx, peak_count);

        // Test C: UART at 33 cycles/bit -> bucket 20
        do_clear; sig = 1; wait_clk(300);
        for (n = 0; n < 40; n = n + 1) begin
            rnd = $random;
            send_uart_byte(rnd, 33);
        end
        send_uart_byte(8'h55, 33); send_uart_byte(8'h55, 33);
        do_scan;
        if (peak_idx !== exp_c) begin
            $display("FAIL C: peak_idx=%0d count=%0d (expected %0d)", peak_idx, peak_count, exp_c);
            errors = errors + 1;
        end else $display("PASS C: UART 33 cyc/bit -> bucket %0d, count %0d", peak_idx, peak_count);

        // Test D: idle pulse after a long gap with no edges
        idle_seen = 0;
        wait_clk(70000);
        if (idle_seen !== 1) begin
            $display("FAIL D: idle pulses = %0d (expected 1)", idle_seen);
            errors = errors + 1;
        end else $display("PASS D: idle pulse seen once after long gap");

        // Test E: no spurious event after idle until two edges arrive
        do_clear;
        sig = ~sig; wait_clk(50);       // first edge after idle: no measurement yet
        do_scan;
        if (peak_count !== 0) begin
            $display("FAIL E: counted an interval after idle with only one edge");
            errors = errors + 1;
        end else $display("PASS E: first edge after idle starts a new measurement");

        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $finish;
    end

    initial begin #200000000; $display("TIMEOUT"); $finish; end
endmodule
