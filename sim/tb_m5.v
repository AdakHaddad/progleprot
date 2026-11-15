`timescale 1ns/1ps
module tb_m5;
    parameter CNT_W = 16;
    parameter FRAC = 1;
    parameter BIN_W = 8;
    parameter NUM_PINS = 8;
    localparam IDX_W = 4 + FRAC;

    reg clk = 0, rst_n = 0;
    reg [NUM_PINS-1:0] pins_in = 8'hFF;
    reg clear = 0, scan_start = 0;

    wire [NUM_PINS*3-1:0] pin_roles;
    wire [NUM_PINS-1:0] role_valid;
    wire idle, scan_done;
    wire [IDX_W-1:0] peak_idx;
    wire [BIN_W-1:0] peak_count;

    wire result_valid;
    wire [3:0] result_proto;
    wire [7:0] result_conf;
    wire [3:0] result_rank;
    wire list_done;
    wire ambiguous;

    integer errors = 0;

    m5_top #(.CNT_W(CNT_W), .FRAC(FRAC), .BIN_W(BIN_W), .NUM_PINS(NUM_PINS)) dut (
        .clk(clk), .rst_n(rst_n),
        .pins_in(pins_in),
        .clear(clear), .scan_start(scan_start),
        .pin_roles(pin_roles), .role_valid(role_valid),
        .idle(idle), .peak_idx(peak_idx), .peak_count(peak_count), .scan_done(scan_done),
        .result_valid(result_valid), .result_proto(result_proto), .result_conf(result_conf),
        .result_rank(result_rank), .list_done(list_done), .ambiguous(ambiguous)
    );

    always #5 clk = ~clk;

    // Debug: monitor pin_role_discovery internal state
    wire [1:0] prd_st = dut.u_prd.st;
    wire [8:0] prd_ev_cnt = dut.u_prd.ev_cnt;
    wire [3:0] prd_pin_edge_cnt_0 = dut.u_prd.pin_edge_cnt[0];
    wire [3:0] prd_pin_edge_cnt_1 = dut.u_prd.pin_edge_cnt[1];
    wire [3:0] prd_pin_edge_cnt_2 = dut.u_prd.pin_edge_cnt[2];
    wire [3:0] prd_pin_edge_cnt_3 = dut.u_prd.pin_edge_cnt[3];
    wire [3:0] prd_pin_edge_cnt_4 = dut.u_prd.pin_edge_cnt[4];
    wire [3:0] prd_pin_edge_cnt_5 = dut.u_prd.pin_edge_cnt[5];
    wire [7:0] prd_corr_0_1 = dut.u_prd.corr_cnt[0][1];
    wire [7:0] prd_corr_2_3 = dut.u_prd.corr_cnt[2][3];
    wire [NUM_PINS-1:0] prd_is_clock = dut.u_prd.is_clock_candidate;
    wire [NUM_PINS-1:0] prd_is_cs = dut.u_prd.is_cs;
    wire [NUM_PINS-1:0] prd_pin_ev = dut.u_prd.pin_ev;
    wire [NUM_PINS-1:0] prd_pin_idle = dut.u_prd.pin_idle;
    wire [CNT_W-1:0] prd_min_0 = dut.u_prd.pin_min_interval[0];
    wire [CNT_W-1:0] prd_max_0 = dut.u_prd.pin_max_interval[0];
    wire [CNT_W-1:0] prd_min_1 = dut.u_prd.pin_min_interval[1];
    wire [CNT_W-1:0] prd_max_1 = dut.u_prd.pin_max_interval[1];
    wire [CNT_W-1:0] prd_min_4 = dut.u_prd.pin_min_interval[4];
    wire [CNT_W-1:0] prd_max_4 = dut.u_prd.pin_max_interval[4];
    wire [CNT_W-1:0] prd_typical_0 = dut.u_prd.pin_typical_interval[0];
    wire [7:0] prd_samples_0 = dut.u_prd.pin_interval_samples[0];
    wire [CNT_W-1:0] prd_typical_1 = dut.u_prd.pin_typical_interval[1];
    wire [7:0] prd_samples_1 = dut.u_prd.pin_interval_samples[1];
    wire [CNT_W-1:0] prd_typical_2 = dut.u_prd.pin_typical_interval[2];
    wire [7:0] prd_samples_2 = dut.u_prd.pin_interval_samples[2];
    wire [CNT_W-1:0] prd_typical_3 = dut.u_prd.pin_typical_interval[3];
    wire [7:0] prd_samples_3 = dut.u_prd.pin_interval_samples[3];
    wire [CNT_W-1:0] prd_typical_4 = dut.u_prd.pin_typical_interval[4];
    wire [7:0] prd_samples_4 = dut.u_prd.pin_interval_samples[4];
    wire [CNT_W-1:0] prd_typical_5 = dut.u_prd.pin_typical_interval[5];
    wire [7:0] prd_samples_5 = dut.u_prd.pin_interval_samples[5];
    wire [7:0] prd_high_0 = dut.u_prd.pin_high_cycles[0];
    wire [7:0] prd_low_0 = dut.u_prd.pin_low_cycles[0];
    wire [7:0] prd_high_4 = dut.u_prd.pin_high_cycles[4];
    wire [7:0] prd_low_4 = dut.u_prd.pin_low_cycles[4];

    // Monitor
    always @(posedge clk) begin
        if (result_valid) $display("  Rank %0d: proto=%0d conf=%0d", result_rank, result_proto, result_conf);
        if (list_done) $display("  [list_done] ambiguous=%0b", ambiguous);
        if (scan_done) $display("  [scan_done] at t=%0t", $time);
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
            $display("  [do_scan] waiting for scan_done...");
            @(negedge clk); scan_start = 1; @(negedge clk); scan_start = 0; 
            wait (scan_done); 
            @(negedge clk); 
            $display("  [do_scan] scan_done received");
        end
    endtask

    task wait_for_list_done;
        integer timeout;
        begin
            $display("  [wait_for_list_done] waiting...");
            timeout = 0;
            while (timeout < 5000) begin
                @(posedge clk);
                if (list_done) begin
                    wait_clk(2);
                    $display("  [wait_for_list_done] done");
                end
                timeout = timeout + 1;
            end
            if (timeout >= 5000) $display("  [wait_for_list_done] TIMEOUT!");
        end
    endtask

    // Drive pins
    // SPI: pin[0]=SCK, pin[1]=MOSI, pin[4]=CS
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

    // I2C: pin[2]=SDA, pin[3]=SCL
    reg sda_drive;
    reg sda_drive_en;
    always @* begin
        if (sda_drive_en) pins_in[2] = sda_drive;
    end

    task i2c_start;
        begin
            sda_drive_en = 0;
            pins_in[2] = 1; pins_in[3] = 1; wait_clk(6);
            pins_in[2] = 0; wait_clk(6);
            pins_in[3] = 0; wait_clk(4);
        end
    endtask

    task i2c_stop;
        begin
            sda_drive_en = 0;
            pins_in[3] = 1; wait_clk(6);
            pins_in[2] = 1; wait_clk(6);
        end
    endtask

    task i2c_write_bit(input bit_val);
        begin
            sda_drive_en = 0;
            pins_in[2] = bit_val; wait_clk(2);
            pins_in[3] = 1; wait_clk(6);
            pins_in[3] = 0; wait_clk(4);
        end
    endtask

    task i2c_slave_ack;
        begin
            sda_drive_en = 1; sda_drive = 0; wait_clk(2);
            pins_in[3] = 1; wait_clk(6);
            pins_in[3] = 0; wait_clk(4);
            sda_drive_en = 0;
        end
    endtask

    task i2c_send_byte(input [7:0] byte_val);
        integer i;
        begin
            for (i = 7; i >= 0; i = i - 1) i2c_write_bit(byte_val[i]);
            i2c_slave_ack;
        end
    endtask

    // UART: pin[5]=TX
    task uart_send_byte(input [7:0] data, input integer bit_period);
        integer i;
        begin
            pins_in[5] = 0; wait_clk(bit_period);
            for (i = 0; i < 8; i = i + 1) begin
                pins_in[5] = data[i]; wait_clk(bit_period);
            end
            pins_in[5] = 1; wait_clk(bit_period);
            wait_clk(bit_period * 2);
        end
    endtask

    initial begin
        sda_drive = 1;
        sda_drive_en = 0;

        wait_clk(4); rst_n = 1; wait_clk(4);
        do_clear();

        $display("Test: Pin-role discovery with SPI, I2C, UART");

        // Generate traffic continuously
        repeat (20) begin
            // SPI on pins 0,1,4
            spi_send_frame(16'hA5, 8, 20);
            wait_clk(30);

            // I2C on pins 2,3
            i2c_start;
            i2c_send_byte(8'hA0);
            i2c_send_byte(8'h55);
            i2c_stop;
            wait_clk(50);

            // UART on pin 5
            uart_send_byte(8'h55, 100);
            wait_clk(50);
        end

        // Extra time for collection
        wait_clk(1000);

        // Debug: print collected stats
        $display("  Pre-scan stats: ev_cnt=%0d, st=%0d", prd_ev_cnt, prd_st);
        $display("  Edge counts: p0=%0d p1=%0d p2=%0d p3=%0d p4=%0d p5=%0d", 
                 prd_pin_edge_cnt_0, prd_pin_edge_cnt_1, prd_pin_edge_cnt_2, 
                 prd_pin_edge_cnt_3, prd_pin_edge_cnt_4, prd_pin_edge_cnt_5);
        $display("  Min/Max/Typical/Samples:");
        $display("    p0: min=%0d max=%0d typical=%0d samples=%0d", prd_min_0, prd_max_0, prd_typical_0, prd_samples_0);
        $display("    p1: min=%0d max=%0d typical=%0d samples=%0d", prd_min_1, prd_max_1, prd_typical_1, prd_samples_1);
        $display("    p2: min=%0d max=%0d typical=%0d samples=%0d", prd_min_0, prd_max_0, prd_typical_2, prd_samples_2);
        $display("    p3: min=%0d max=%0d typical=%0d samples=%0d", prd_min_0, prd_max_0, prd_typical_3, prd_samples_3);
        $display("    p4: min=%0d max=%0d typical=%0d samples=%0d high=%0d low=%0d", prd_min_4, prd_max_4, prd_typical_4, prd_samples_4, prd_high_4, prd_low_4);
        $display("    p5: min=%0d max=%0d typical=%0d samples=%0d", prd_min_0, prd_max_0, prd_typical_5, prd_samples_5);
        $display("  Corr: 0-1=%0d, 2-3=%0d", prd_corr_0_1, prd_corr_2_3);
        $display("  pin_ev: %b, pin_idle: %b", prd_pin_ev, prd_pin_idle);
        $display("  is_clock: %b, is_cs: %b", prd_is_clock, prd_is_cs);

        do_scan();
        wait_for_list_done();

        // Check role assignments
        $display("Pin role assignments:");
        for (integer p = 0; p < NUM_PINS; p = p + 1) begin
            $display("  Pin %0d: role=%0d (%s), valid=%0b",
                     p, pin_roles[p*3 +: 3],
                     (pin_roles[p*3 +: 3] == 3'd0) ? "UNUSED" :
                     (pin_roles[p*3 +: 3] == 3'd1) ? "CLK" :
                     (pin_roles[p*3 +: 3] == 3'd2) ? "DATA" :
                     (pin_roles[p*3 +: 3] == 3'd3) ? "CS" :
                     (pin_roles[p*3 +: 3] == 3'd4) ? "TX" :
                     (pin_roles[p*3 +: 3] == 3'd5) ? "RX" :
                     (pin_roles[p*3 +: 3] == 3'd6) ? "SDA" :
                     (pin_roles[p*3 +: 3] == 3'd7) ? "SCL" : "???",
                     role_valid[p]);
        end

        // Verify expected roles
        if (pin_roles[0*3 +: 3] != 3'd1) begin
            $display("  FAIL: Pin 0 expected CLK(1), got %0d", pin_roles[0*3 +: 3]);
            errors = errors + 1;
        end
        if (pin_roles[1*3 +: 3] != 3'd2) begin
            $display("  FAIL: Pin 1 expected DATA(2), got %0d", pin_roles[1*3 +: 3]);
            errors = errors + 1;
        end
        if (pin_roles[3*3 +: 3] != 3'd1 && pin_roles[3*3 +: 3] != 3'd7) begin
            $display("  FAIL: Pin 3 expected SCL(7) or CLK(1), got %0d", pin_roles[3*3 +: 3]);
            errors = errors + 1;
        end
        if (pin_roles[4*3 +: 3] != 3'd3) begin
            $display("  FAIL: Pin 4 expected CS(3), got %0d", pin_roles[4*3 +: 3]);
            errors = errors + 1;
        end
        if (pin_roles[5*3 +: 3] != 3'd4 && pin_roles[5*3 +: 3] != 3'd5) begin
            $display("  FAIL: Pin 5 expected TX(4)/RX(5), got %0d", pin_roles[5*3 +: 3]);
            errors = errors + 1;
        end

        if (errors == 0) $display("ALL TESTS PASSED");
        else $display("%0d TEST(S) FAILED", errors);
        $finish;
    end

    initial begin #30000000; $display("GLOBAL TIMEOUT"); $finish; end
endmodule
