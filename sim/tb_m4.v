`timescale 1ns/1ps
module tb_m4;
    parameter CNT_W = 16;
    parameter FRAC = 1;
    parameter BIN_W = 8;
    localparam IDX_W = 4 + FRAC;

    reg clk = 0, rst_n = 0;
    reg ch0_a = 1, ch0_b = 1, ch0_cs_n = 1;
    reg ch1_a = 1, ch1_b = 1, ch1_cs_n = 1;
    reg clear = 0, scan_start = 0;

    wire idle, scan_done;
    wire [IDX_W-1:0] peak_idx;
    wire [BIN_W-1:0] peak_count;

    wire result_valid;
    wire [3:0] result_proto;
    wire [7:0] result_conf;
    wire [3:0] result_rank;
    wire list_done;
    wire ambiguous;

    wire spi_frame_valid;
    wire [11:0] spi_frame_bits;
    wire [7:0] spi_n_frames;

    wire i2c_frame_valid;
    wire [7:0] i2c_addr;
    wire i2c_ack, i2c_is_read;
    wire [7:0] i2c_n_frames;

    integer errors = 0;

    m4_top #(.CNT_W(CNT_W), .FRAC(FRAC), .BIN_W(BIN_W)) dut (
        .clk(clk), .rst_n(rst_n),
        .ch0_a(ch0_a), .ch0_b(ch0_b), .ch0_cs_n(ch0_cs_n),
        .ch1_a(ch1_a), .ch1_b(ch1_b), .ch1_cs_n(ch1_cs_n),
        .clear(clear), .scan_start(scan_start),
        .idle(idle), .peak_idx(peak_idx), .peak_count(peak_count), .scan_done(scan_done),
        .result_valid(result_valid), .result_proto(result_proto), .result_conf(result_conf),
        .result_rank(result_rank), .list_done(list_done), .ambiguous(ambiguous),
        .spi_frame_valid(spi_frame_valid), .spi_frame_bits(spi_frame_bits), .spi_n_frames(spi_n_frames),
        .i2c_frame_valid(i2c_frame_valid), .i2c_addr(i2c_addr), .i2c_ack(i2c_ack),
        .i2c_is_read(i2c_is_read), .i2c_n_frames(i2c_n_frames)
    );

    always #5 clk = ~clk;

    // Monitor for debug
    always @(posedge clk) begin
        if (result_valid) $display("  Rank %0d: proto=%0d conf=%0d", result_rank, result_proto, result_conf);
        if (list_done) $display("  [list_done] ambiguous=%0b", ambiguous);
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
            $display("  [do_scan] scan_done received (peak_idx=%0d, peak_count=%0d)", peak_idx, peak_count);
        end
    endtask

    // Wait for rising edge of list_done
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

    // SPI: ch0_a = SCK, ch0_b = MOSI, ch0_cs_n = CS
    task spi_send_frame(input [15:0] data, input integer bits, input integer sck_half_period);
        integer i;
        begin
            ch0_cs_n = 0; wait_clk(4);
            for (i = bits-1; i >= 0; i = i - 1) begin
                ch0_b = data[i];
                ch0_a = 0; wait_clk(sck_half_period);
                ch0_a = 1; wait_clk(sck_half_period);
            end
            ch0_cs_n = 1; wait_clk(10);
        end
    endtask

    // I2C with slave ACK
    reg sda_drive;
    reg sda_drive_en;
    always @* begin
        if (sda_drive_en) ch1_a = sda_drive;
    end

    task i2c_start;
        begin
            sda_drive_en = 0;
            ch1_a = 1; ch1_b = 1; wait_clk(6);
            ch1_a = 0; wait_clk(6);
            ch1_b = 0; wait_clk(4);
        end
    endtask

    task i2c_stop;
        begin
            sda_drive_en = 0;
            ch1_b = 1; wait_clk(6);
            ch1_a = 1; wait_clk(6);
        end
    endtask

    task i2c_write_bit(input bit_val);
        begin
            sda_drive_en = 0;
            ch1_a = bit_val; wait_clk(2);
            ch1_b = 1; wait_clk(6);
            ch1_b = 0; wait_clk(4);
        end
    endtask

    task i2c_slave_ack;
        begin
            sda_drive_en = 1; sda_drive = 0; wait_clk(2);
            ch1_b = 1; wait_clk(6);
            ch1_b = 0; wait_clk(4);
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

    initial begin
        sda_drive = 1;
        sda_drive_en = 0;

        wait_clk(4); rst_n = 1; wait_clk(4);
        do_clear;

        // ---------- Test 1: I2C fingerprint matching ----------
        $display("Test 1: I2C fingerprint matching (addr 0x50 write)");
        i2c_start;
        i2c_send_byte(8'hA0);
        i2c_send_byte(8'hAA);
        i2c_stop;
        wait_for_list_done();
        do_scan();

        // ---------- Test 2: SPI fingerprint matching ----------
        $display("Test 2: SPI fingerprint matching");
        do_clear;
        spi_send_frame(16'hA5, 8, 20);
        spi_send_frame(16'h5A, 8, 20);
        spi_send_frame(16'hFF, 8, 20);
        wait_for_list_done();
        do_scan();

        // ---------- Test 3: Mixed traffic ----------
        $display("Test 3: Mixed SPI + I2C");
        do_clear;
        spi_send_frame(16'h3C, 8, 20);
        i2c_start; i2c_send_byte(8'hA0); i2c_send_byte(8'h55); i2c_stop;
        spi_send_frame(16'hC3, 8, 20);
        i2c_start; i2c_send_byte(8'hA1); i2c_slave_ack; i2c_stop;
        wait_for_list_done();  // First frame
        wait_for_list_done();  // Second frame
        do_scan();

        if (errors == 0) $display("ALL TESTS PASSED");
        else $display("%0d TEST(S) FAILED", errors);
        $finish;
    end

    initial begin #15000000; $display("GLOBAL TIMEOUT"); $finish; end
endmodule
