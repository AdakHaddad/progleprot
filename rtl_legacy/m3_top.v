// m3_top: SPI and I²C detection sharing the histogram pipeline.
// Two independent input channels (pin pairs). Each channel runs edge_interval -> log_bucket -> histogram.
// A shared peak_detect scans the combined histogram. Then SPI/I²C detectors run on their respective pins.
// Updated: Added encoding_layer (NRZ/NRZI/Manchester/Stuffing) before protocol detectors.
// Note: Encoding layer applied to SPI data line (ch0_a). I2C uses raw signals directly.
module m3_top #(
    parameter CNT_W     = 16,
    parameter FRAC      = 1,
    parameter BIN_W     = 8,
    parameter IDX_W     = $clog2(CNT_W) + FRAC,
    parameter N_COLLECT = 128
) (
    input  wire             clk,
    input  wire             rst_n,
    // Channel 0 pins (e.g., SPI: SCK, MOSI/MISO; I2C: SCL, SDA)
    input  wire             ch0_a,
    input  wire             ch0_b,
    input  wire             ch0_cs_n,   // optional CS for SPI
    // Channel 1 pins
    input  wire             ch1_a,
    input  wire             ch1_b,
    input  wire             ch1_cs_n,
    // Control
    input  wire             clear,
    input  wire             scan_start,
    // Encoding mode for channel 0 (SPI data line)
    input  wire [1:0]       ch0_enc_mode,
    input  wire [3:0]       ch0_stuff_after,
    // Outputs
    output wire             idle,
    output wire [IDX_W-1:0] peak_idx,
    output wire [BIN_W-1:0] peak_count,
    output wire             scan_done,
    // SPI results
    output wire             spi_role_a_is_clk,
    output wire [1:0]       spi_mode,
    output wire             spi_frame_valid,
    output wire [11:0]      spi_frame_bits,
    output wire [7:0]       spi_n_frames,
    // I2C results
    output wire             i2c_frame_valid,
    output wire [7:0]       i2c_addr,
    output wire             i2c_ack,
    output wire             i2c_is_read,
    output wire [7:0]       i2c_n_frames
);

    // Channel 0: edge_interval -> log_bucket -> histogram
    wire              ch0_ev, ch0_idle, ch0_level;
    wire [CNT_W-1:0]  ch0_interval;
    wire [IDX_W-1:0]  ch0_bucket;

    edge_interval #(.CNT_W(CNT_W)) u_ei0 (
        .clk(clk), .rst_n(rst_n), .signal_in(ch0_a),
        .event_valid(ch0_ev), .interval_cycles(ch0_interval), .idle(ch0_idle), .level(ch0_level));

    log_bucket #(.W(CNT_W), .FRAC(FRAC)) u_lb0 (.x(ch0_interval), .idx(ch0_bucket));

    // Channel 1: edge_interval -> log_bucket -> histogram
    wire              ch1_ev, ch1_idle, ch1_level;
    wire [CNT_W-1:0]  ch1_interval;
    wire [IDX_W-1:0]  ch1_bucket;

    edge_interval #(.CNT_W(CNT_W)) u_ei1 (
        .clk(clk), .rst_n(rst_n), .signal_in(ch1_a),
        .event_valid(ch1_ev), .interval_cycles(ch1_interval), .idle(ch1_idle), .level(ch1_level));

    log_bucket #(.W(CNT_W), .FRAC(FRAC)) u_lb1 (.x(ch1_interval), .idx(ch1_bucket));

    // Shared histogram (both channels feed into same histogram)
    wire [IDX_W-1:0]  hist_rd_idx;
    wire [BIN_W-1:0]  hist_rd_data;

    histogram #(.IDX_W(IDX_W), .CNT_W(BIN_W)) u_hist (
        .clk(clk), .rst_n(rst_n), .clear(clear),
        .inc_valid(ch0_ev | ch1_ev),
        .inc_idx(ch0_ev ? ch0_bucket : ch1_bucket),
        .rd_idx(hist_rd_idx), .rd_data(hist_rd_data));

    // Peak detector
    wire pk_busy;
    peak_detect #(.IDX_W(IDX_W), .CNT_W(BIN_W)) u_pk (
        .clk(clk), .rst_n(rst_n), .start(scan_start),
        .rd_idx(hist_rd_idx), .rd_data(hist_rd_data),
        .peak_idx(peak_idx), .peak_count(peak_count),
        .done(scan_done), .busy(pk_busy));

    assign idle = ch0_idle | ch1_idle;

    // ============================================================
    // Encoding Layer - decodes raw bits before protocol detection
    // Applied to SPI data line (ch0_a) only. I2C uses raw signals.
    // ============================================================
    wire                    ch0_enc_bit_valid;
    wire                    ch0_enc_bit_out;

    // Channel 0 encoding layer (SPI MOSI/MISO line)
    encoding_layer #(.CNT_W(CNT_W)) u_enc0 (
        .clk(clk),
        .rst_n(rst_n),
        .mode(ch0_enc_mode),
        .bit_in(ch0_a),           // raw signal
        .bit_valid(ch0_ev),       // edge_interval event as bit_valid
        .bit_out(ch0_enc_bit_out),
        .bit_out_valid(ch0_enc_bit_valid),
        .stuff_after(ch0_stuff_after),
        .stuff_error()
    );

    // Decoded bit stream for SPI detector
    wire ch0_decoded_a = ch0_enc_bit_out;
    wire ch0_decoded_b = ch0_b;  // Second pin passes through (clock for SPI)

    // SPI detector on channel 0
    spi_detect #(.CNT_W(CNT_W), .IDX_W(IDX_W), .BIN_W(BIN_W)) u_spi (
        .clk(clk), .rst_n(rst_n),
        .pin_a(ch0_decoded_a), .pin_b(ch0_decoded_b), .cs_n(ch0_cs_n),
        .hist_ev(ch0_ev), .hist_interval(ch0_interval), .hist_bucket(ch0_bucket),
        .role_a_is_clk(spi_role_a_is_clk), .mode(spi_mode),
        .frame_valid(spi_frame_valid), .frame_bits(spi_frame_bits), .n_frames(spi_n_frames));

    // I2C detector on channel 1 - uses RAW signals directly (no encoding layer)
    i2c_detect #(.CNT_W(CNT_W)) u_i2c (
        .clk(clk), .rst_n(rst_n),
        .sda(ch1_a), .scl(ch1_b),
        .frame_valid(i2c_frame_valid), .addr(i2c_addr), .ack(i2c_ack),
        .is_read(i2c_is_read), .n_frames(i2c_n_frames));

endmodule
