`timescale 1ns/1ps
module tb_m3;
    parameter CNT_W = 16;
    parameter FRAC = 1;
    parameter BIN_W = 8;
    localparam IDX_W = 4 + FRAC;

    reg clk = 0, rst_n = 0;
    reg ch0_a = 1, ch0_b = 1, ch0_cs_n = 1;
    reg ch1_a = 1, ch1_b = 1, ch1_cs_n = 1;
    reg clear = 0, scan_start = 0;
    // Encoding layer inputs for channel 0 (SPI data line) only
    reg [1:0] ch0_enc_mode = 2'd0;
    reg [3:0] ch0_stuff_after = 4'd0;

    wire idle, scan_done;
    wire [IDX_W-1:0] peak_idx;
    wire [BIN_W-1:0] peak_count;

    wire spi_role_a_is_clk;
    wire [1:0] spi_mode;
    wire spi_frame_valid;
    wire [11:0] spi_frame_bits;
    wire [7:0] spi_n_frames;

    wire i2c_frame_valid;
    wire [7:0] i2c_addr;
    wire i2c_ack, i2c_is_read;
    wire [7:0] i2c_n_frames;

    integer errors = 0;

    m3_top #(.CNT_W(CNT_W), .FRAC(FRAC), .BIN_W(BIN_W)) dut (
        .clk(clk), .rst_n(rst_n),
        .ch0_a(ch0_a), .ch0_b(ch0_b), .ch0_cs_n(ch0_cs_n),
        .ch1_a(ch1_a), .ch1_b(ch1_b), .ch1_cs_n(ch1_cs_n),
        .clear(clear), .scan_start(scan_start),
        .ch0_enc_mode(ch0_enc_mode), .ch0_stuff_after(ch0_stuff_after),
        .idle(idle), .peak_idx(peak_idx), .peak_count(peak_count), .scan_done(scan_done),
        .spi_role_a_is_clk(spi_role_a_is_clk), .spi_mode(spi_mode),
        .spi_frame_valid(spi_frame_valid), .spi_frame_bits(spi_frame_bits), .spi_n_frames(spi_n_frames),
        .i2c_frame_valid(i2c_frame_valid), .i2c_addr(i2c_addr), .i2c_ack(i2c_ack),
        .i2c_is_read(i2c_is_read), .i2c_n_frames(i2c_n_frames)
    );

    always #5 clk = ~clk;

    // Debug: monitor I2C internal state
    wire [1:0] i2c_st = dut.u_i2c.st;
    wire [3:0] i2c_bit_cnt = dut.u_i2c.bit_cnt;
    wire [7:0] i2c_shift = dut.u_i2c.shift_reg;
    wire i2c_start_cond = dut.u_i2c.sda_q3 && !dut.u_i2c.sda_q2 && dut.u_i2c.scl_q2;
    wire i2c_stop_cond = !dut.u_i2c.sda_q3 && dut.u_i2c.sda_q2 && dut.u_i2c.scl_q2;

    // Debug: monitor SPI internal state
    wire [1:0] spi_st = dut.u_spi.st;
    wire [11:0] spi_bit_cnt = dut.u_spi.bit_cnt;

    task wait_clk(input integer n);
        integer j;
        begin for (j = 0; j < n; j = j + 1) @(negedge clk); end
    endtask

    task do_clear;
        begin @(negedge clk); clear = 1; @(negedge clk); clear = 0; end
    endtask

    task do_scan;
        begin @(negedge clk); scan_start = 1; @(negedge clk); scan_start = 0; wait (scan_done); @(negedge clk); end
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

    // I2C: ch1_a = SDA, ch1_b = SCL
    // Simulate slave ACK by pulling SDA low during ACK clock
    reg sda_drive;
    reg sda_drive_en;

    // Override ch1_a when slave drives
    always @* begin
        if (sda_drive_en) ch1_a = sda_drive;
    end

    task i2c_start;
        begin
            sda_drive_en = 0;
            ch1_a = 1; ch1_b = 1; wait_clk(6);
            ch1_a = 0; wait_clk(6);  // SDA falls while SCL high = START
            ch1_b = 0; wait_clk(4);
        end
    endtask

    task i2c_stop;
        begin
            sda_drive_en = 0;
            ch1_b = 1; wait_clk(6);
            ch1_a = 1; wait_clk(6);  // SDA rises while SCL high = STOP
        end
    endtask

    task i2c_write_bit(input bit_val);
        begin
            sda_drive_en = 0;
            ch1_a = bit_val; wait_clk(2);
            ch1_b = 1; wait_clk(6);  // SCL high - data sampled here
            ch1_b = 0; wait_clk(4);
        end
    endtask

    task i2c_slave_ack;
        begin
            // Slave pulls SDA low during ACK clock
            sda_drive_en = 1;
            sda_drive = 0;
            wait_clk(2);
            ch1_b = 1; wait_clk(6);  // SCL high - slave ACK sampled here
            ch1_b = 0; wait_clk(4);
            sda_drive_en = 0;
        end
    endtask

    task i2c_slave_nack;
        begin
            // Slave releases SDA (high) during ACK clock
            sda_drive_en = 1;
            sda_drive = 1;
            wait_clk(2);
            ch1_b = 1; wait_clk(6);
            ch1_b = 0; wait_clk(4);
            sda_drive_en = 0;
        end
    endtask

    task i2c_master_read_ack;
        begin
            // Master releases SDA, slave drives ACK
            sda_drive_en = 0;
            wait_clk(2);
            // Slave ACK
            sda_drive_en = 1;
            sda_drive = 0;
            wait_clk(2);
            ch1_b = 1; wait_clk(6);
            ch1_b = 0; wait_clk(4);
            sda_drive_en = 0;
        end
    endtask

    task i2c_send_byte(input [7:0] byte_val);
        integer i;
        begin
            for (i = 7; i >= 0; i = i - 1) i2c_write_bit(byte_val[i]);
            i2c_slave_ack;  // Slave ACKs
        end
    endtask

    initial begin
        sda_drive = 1;
        sda_drive_en = 0;

        // Reset
        wait_clk(4); rst_n = 1; wait_clk(4);

        do_clear;

        // ---------- Test 1: SPI detection ----------
        $display("Test 1: SPI frames");
        spi_send_frame(16'hA5, 8, 20);
        spi_send_frame(16'h5A, 8, 20);
        spi_send_frame(16'hFF, 8, 20);
        spi_send_frame(16'h00, 8, 20);

        // Scan histogram
        do_scan;
        $display("  Peak idx=%0d, count=%0d", peak_idx, peak_count);

        // Wait for SPI frames to be detected
        wait_clk(5000);
        $display("  SPI: st=%0d, role_a_clk=%0b, mode=%0b, frames=%0d, bits=%0d, bit_cnt=%0d",
                 spi_st, spi_role_a_is_clk, spi_mode, spi_n_frames, spi_frame_bits, spi_bit_cnt);
        if (spi_n_frames < 3) begin
            $display("  FAIL: Expected >=3 SPI frames, got %0d", spi_n_frames);
            errors = errors + 1;
        end else begin
            $display("  PASS: SPI detected");
        end

        // ---------- Test 2: I2C detection ----------
        $display("Test 2: I2C frames");
        do_clear;

        // I2C write: address 0x50 (7-bit) + W=0, ACK, data 0xAA, ACK, STOP
        i2c_start;
        i2c_send_byte(8'hA0);  // 0x50 << 1 | 0 (write)
        i2c_send_byte(8'hAA);
        i2c_stop;
        wait_clk(100);

        // I2C read: address 0x50 + R=1, ACK, master reads byte, NACK, STOP
        i2c_start;
        i2c_send_byte(8'hA1);  // 0x50 << 1 | 1 (read)
        // Master reads byte (slave drives data), master NACKs
        i2c_master_read_ack;  // Slave sends data byte + ACK
        i2c_slave_nack;       // Master NACKs (simulated as slave NACK for simplicity)
        i2c_stop;
        wait_clk(100);

        do_scan;
        wait_clk(5000);

        $display("  I2C: st=%0d, frames=%0d, addr=0x%02h, ack=%0b, is_read=%0d, bit_cnt=%0d, shift=0x%02h",
                 i2c_st, i2c_n_frames, i2c_addr, i2c_ack, i2c_is_read, i2c_bit_cnt, i2c_shift);
        $display("  start_cond=%0b, stop_cond=%0b, sda_q1=%0b, sda_q2=%0b, sda_q3=%0b, scl_q1=%0b, scl_q2=%0b, scl_q3=%0b",
                 i2c_start_cond, i2c_stop_cond, 
                 dut.u_i2c.sda_q1, dut.u_i2c.sda_q2, dut.u_i2c.sda_q3,
                 dut.u_i2c.scl_q1, dut.u_i2c.scl_q2, dut.u_i2c.scl_q3);
        if (i2c_n_frames < 1) begin
            $display("  FAIL: Expected >=1 I2C frame");
            errors = errors + 1;
        end else begin
            $display("  PASS: I2C detected");
        end

        // ---------- Test 3: Mixed traffic ----------
        $display("Test 3: Mixed SPI + I2C");
        do_clear;

        // Interleave SPI and I2C
        spi_send_frame(16'h3C, 8, 20);
        i2c_start; i2c_send_byte(8'hA0); i2c_send_byte(8'h55); i2c_stop;
        spi_send_frame(16'hC3, 8, 20);
        i2c_start; i2c_send_byte(8'hA1); i2c_master_read_ack; i2c_slave_nack; i2c_stop;
        wait_clk(500);

        do_scan;
        wait_clk(5000);

        $display("  SPI frames=%0d, I2C frames=%0d", spi_n_frames, i2c_n_frames);

        if (errors == 0) $display("ALL TESTS PASSED");
        else $display("%0d TEST(S) FAILED", errors);
        $finish;
    end

    initial begin #5000000; $display("TIMEOUT"); $finish; end
endmodule
