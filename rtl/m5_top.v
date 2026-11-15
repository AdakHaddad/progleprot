// m5_top: Protocol discovery with pin-role discovery.
// Extends M4: adds pin_role_discovery that analyzes all input pins
// and assigns roles (clk, data, cs, tx, rx, sda, scl).
module m5_top #(
    parameter CNT_W     = 16,
    parameter FRAC      = 1,
    parameter BIN_W     = 8,
    parameter IDX_W     = $clog2(CNT_W) + FRAC,
    parameter NUM_PINS  = 8,
    parameter N_COLLECT = 1024,
    parameter MAX_PRINTS = 16,
    parameter MAX_PATTERN_BITS = 64,
    parameter FRAME_BITS = 32,
    parameter MAX_RESULTS = 8
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire [NUM_PINS-1:0]     pins_in,      // All input pins
    // Control
    input  wire                    clear,
    input  wire                    scan_start,
    // Pin role outputs
    output wire [NUM_PINS*3-1:0]   pin_roles,    // 3 bits per pin
    output wire [NUM_PINS-1:0]     role_valid,
    // Ranked protocol output
    output wire                    result_valid,
    output wire [3:0]              result_proto,
    output wire [7:0]              result_conf,
    output wire [3:0]              result_rank,
    output wire                    list_done,
    output wire                    ambiguous,
    // Debug/status
    output wire                    idle,
    output wire [IDX_W-1:0]        peak_idx,
    output wire [BIN_W-1:0]        peak_count,
    output wire                    scan_done
);

    // Pin role discovery (analyzes all pins)
    pin_role_discovery #(
        .NUM_PINS(NUM_PINS),
        .CNT_W(CNT_W),
        .FRAC(FRAC),
        .BIN_W(BIN_W),
        .IDX_W(IDX_W),
        .N_COLLECT(N_COLLECT)
    ) u_prd (
        .clk(clk), .rst_n(rst_n),
        .pins_in(pins_in),
        .clear(clear), .scan_start(scan_start),
        .pin_roles(pin_roles), .role_valid(role_valid),
        .idle(idle), .peak_idx(peak_idx), .peak_count(peak_count), .scan_done(scan_done));

    // For backward compatibility, also run M4 pipeline on first 2 channels
    // Channel 0: pins_in[0], pins_in[1]
    // Channel 1: pins_in[2], pins_in[3]
    wire              ch0_ev, ch0_idle, ch0_level;
    wire [CNT_W-1:0]  ch0_interval;
    wire [IDX_W-1:0]  ch0_bucket;

    edge_interval #(.CNT_W(CNT_W)) u_ei0 (
        .clk(clk), .rst_n(rst_n), .signal_in(pins_in[0]),
        .event_valid(ch0_ev), .interval_cycles(ch0_interval), .idle(ch0_idle), .level(ch0_level));

    log_bucket #(.W(CNT_W), .FRAC(FRAC)) u_lb0 (.x(ch0_interval), .idx(ch0_bucket));

    wire              ch1_ev, ch1_idle, ch1_level;
    wire [CNT_W-1:0]  ch1_interval;
    wire [IDX_W-1:0]  ch1_bucket;

    edge_interval #(.CNT_W(CNT_W)) u_ei1 (
        .clk(clk), .rst_n(rst_n), .signal_in(pins_in[2]),
        .event_valid(ch1_ev), .interval_cycles(ch1_interval), .idle(ch1_idle), .level(ch1_level));

    log_bucket #(.W(CNT_W), .FRAC(FRAC)) u_lb1 (.x(ch1_interval), .idx(ch1_bucket));

    // Shared histogram
    wire [IDX_W-1:0]  hist_rd_idx;
    wire [BIN_W-1:0]  hist_rd_data;

    histogram #(.IDX_W(IDX_W), .CNT_W(BIN_W)) u_hist (
        .clk(clk), .rst_n(rst_n), .clear(clear),
        .inc_valid(ch0_ev | ch1_ev),
        .inc_idx(ch0_ev ? ch0_bucket : ch1_bucket),
        .rd_idx(hist_rd_idx), .rd_data(hist_rd_data));

    // Peak detector (for M4 compatibility)
    wire pk_busy;
    peak_detect #(.IDX_W(IDX_W), .CNT_W(BIN_W)) u_pk (
        .clk(clk), .rst_n(rst_n), .start(scan_start),
        .rd_idx(hist_rd_idx), .rd_data(hist_rd_data),
        .peak_idx(peak_idx), .peak_count(peak_count),
        .done(scan_done), .busy(pk_busy));

    // SPI detector on channel 0
    wire                    spi_frame_valid;
    wire [11:0]             spi_frame_bits;
    wire [7:0]              spi_n_frames;

    spi_detect #(.CNT_W(CNT_W), .IDX_W(IDX_W), .BIN_W(BIN_W)) u_spi (
        .clk(clk), .rst_n(rst_n),
        .pin_a(pins_in[0]), .pin_b(pins_in[1]), .cs_n(pins_in[3]),
        .hist_ev(ch0_ev), .hist_interval(ch0_interval), .hist_bucket(ch0_bucket),
        .role_a_is_clk(), .mode(),
        .frame_valid(spi_frame_valid), .frame_bits(spi_frame_bits), .n_frames(spi_n_frames));

    // I2C detector on channel 1
    wire                    i2c_frame_valid;
    wire [7:0]              i2c_addr;
    wire                    i2c_ack, i2c_is_read;
    wire [7:0]              i2c_n_frames;

    i2c_detect #(.CNT_W(CNT_W)) u_i2c (
        .clk(clk), .rst_n(rst_n),
        .sda(pins_in[2]), .scl(pins_in[3]),
        .frame_valid(i2c_frame_valid), .addr(i2c_addr), .ack(i2c_ack),
        .is_read(i2c_is_read), .n_frames(i2c_n_frames));

    // Frame aggregator
    reg                     frame_valid_reg;
    reg [FRAME_BITS-1:0]    frame_data_reg;
    reg [7:0]               frame_len_reg;
    reg [3:0]               frame_proto_hint;
    reg                     hint_valid_reg;
    reg                     new_frame_pulse;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_valid_reg <= 1'b0;
            frame_data_reg <= 32'd0;
            frame_len_reg <= 8'd0;
            frame_proto_hint <= 4'd0;
            hint_valid_reg <= 1'b0;
            new_frame_pulse <= 1'b0;
        end else begin
            frame_valid_reg <= 1'b0;
            new_frame_pulse <= 1'b0;

            if (i2c_frame_valid) begin
                frame_valid_reg <= 1'b1;
                frame_data_reg <= {16'd0, i2c_addr, i2c_ack, i2c_is_read, 6'd0};
                frame_len_reg <= 8'd16;
                frame_proto_hint <= 4'd2;
                hint_valid_reg <= 1'b1;
                new_frame_pulse <= 1'b1;
            end else if (spi_frame_valid) begin
                frame_valid_reg <= 1'b1;
                frame_data_reg <= {20'd0, spi_frame_bits};
                frame_len_reg <= spi_frame_bits[7:0];
                frame_proto_hint <= 4'd1;
                hint_valid_reg <= 1'b1;
                new_frame_pulse <= 1'b1;
            end
        end
    end

    // Fingerprint matcher
    wire                    match_valid;
    wire [3:0]              match_proto;
    wire [7:0]              match_score;
    wire                    match_done;
    wire                    match_busy;

    fingerprint_matcher #(
        .NUM_PRINTS(MAX_PRINTS),
        .MAX_PATTERN_BITS(MAX_PATTERN_BITS),
        .FRAME_BITS(FRAME_BITS)
    ) u_matcher (
        .clk(clk), .rst_n(rst_n),
        .frame_valid(frame_valid_reg),
        .frame_data(frame_data_reg),
        .frame_len(frame_len_reg),
        .proto_hint(frame_proto_hint),
        .hint_valid(hint_valid_reg),
        .match_valid(match_valid),
        .match_proto(match_proto),
        .match_score(match_score),
        .match_len(),  // unused
        .done(match_done),
        .busy(match_busy));

    // Ranked output
    ranked_output #(
        .MAX_RESULTS(MAX_RESULTS),
        .PROTO_BITS(4),
        .SCORE_BITS(8),
        .CONF_BITS(8)
    ) u_ranked (
        .clk(clk), .rst_n(rst_n),
        .match_valid(match_valid),
        .match_proto(match_proto),
        .match_score(match_score),
        .match_done(match_done),
        .new_frame(new_frame_pulse),
        .result_valid(result_valid),
        .result_proto(result_proto),
        .result_conf(result_conf),
        .result_rank(result_rank),
        .list_done(list_done),
        .ambiguous(ambiguous));

endmodule
