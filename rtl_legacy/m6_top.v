// m6_top: Closed-loop protocol discovery and replay.
// Combines pin-role discovery, fingerprint matching, sequencer compilation, and replay.
// Updated: Added encoding_layer (NRZ/NRZI/Manchester/Stuffing) before protocol detectors.
// Note: Encoding layer applied to SPI data line (pins_in[0]). I2C uses raw signals.
module m6_top #(
    parameter CNT_W     = 16,
    parameter FRAC      = 1,
    parameter BIN_W     = 8,
    parameter IDX_W     = $clog2(CNT_W) + FRAC,
    parameter NUM_PINS  = 8,
    parameter N_COLLECT = 1024,
    parameter MAX_PRINTS = 16,
    parameter MAX_PATTERN_BITS = 64,
    parameter FRAME_BITS = 32,
    parameter MAX_RESULTS = 8,
    parameter PROG_DEPTH = 256,
    parameter PROG_W = 32
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire [NUM_PINS-1:0]     pins_in,
    // Control
    input  wire                    clear,
    input  wire                    scan_start,
    input  wire                    replay_start,
    // Encoding mode for protocol detection (channel 0 = SPI data)
    input  wire [1:0]              enc_mode_ch0,
    input  wire [3:0]              stuff_after_ch0,
    // Pin role outputs
    output wire [NUM_PINS*3-1:0]   pin_roles,
    output wire [NUM_PINS-1:0]     role_valid,
    // Ranked protocol output
    output wire                    result_valid,
    output wire [3:0]              result_proto,
    output wire [7:0]              result_conf,
    output wire [3:0]              result_rank,
    output wire                    list_done,
    output wire                    ambiguous,
    // Sequencer outputs
    output wire                    replay_done,
    output wire                    replay_error,
    // Debug/status
    output wire                    idle,
    output wire [IDX_W-1:0]        peak_idx,
    output wire [BIN_W-1:0]        peak_count,
    output wire                    scan_done,
    output wire [7:0]              prog_len,
    output wire [7:0]              seq_pc
);

    // Pin role discovery - provides histogram peak detection for all pins
    wire [NUM_PINS-1:0]           pins_combined;
    assign pins_combined = pins_in;

    pin_role_discovery #(
        .NUM_PINS(NUM_PINS),
        .CNT_W(CNT_W),
        .FRAC(FRAC),
        .BIN_W(BIN_W),
        .IDX_W(IDX_W),
        .N_COLLECT(N_COLLECT)
    ) u_prd (
        .clk(clk), .rst_n(rst_n),
        .pins_in(pins_combined),
        .clear(clear), .scan_start(scan_start),
        .pin_roles(pin_roles), .role_valid(role_valid),
        .idle(idle), .peak_idx(peak_idx), .peak_count(peak_count), .scan_done(scan_done));

    // M4 pipeline for fingerprint matching - dedicated histogram on pins 0,2 (SPI/I2C)
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

    // Shared histogram for fingerprint matching
    wire [IDX_W-1:0]  hist_rd_idx;
    wire [BIN_W-1:0]  hist_rd_data;

    histogram #(.IDX_W(IDX_W), .CNT_W(BIN_W)) u_hist (
        .clk(clk), .rst_n(rst_n), .clear(clear),
        .inc_valid(ch0_ev | ch1_ev),
        .inc_idx(ch0_ev ? ch0_bucket : ch1_bucket),
        .rd_idx(hist_rd_idx), .rd_data(hist_rd_data));

    // Peak detector for fingerprint histogram (internal, not connected to outputs)
    wire fp_peak_done, fp_pk_busy;
    wire [IDX_W-1:0] fp_peak_idx;
    wire [BIN_W-1:0] fp_peak_count;

    peak_detect #(.IDX_W(IDX_W), .CNT_W(BIN_W)) u_fp_pk (
        .clk(clk), .rst_n(rst_n), .start(scan_start),
        .rd_idx(hist_rd_idx), .rd_data(hist_rd_data),
        .peak_idx(fp_peak_idx), .peak_count(fp_peak_count),
        .done(fp_peak_done), .busy(fp_pk_busy));

    // ============================================================
    // Encoding Layer - decodes raw bits before protocol detection
    // Applied to SPI data line (pins_in[0]) only. I2C uses raw signals.
    // ============================================================
    wire                    ch0_enc_bit_valid;
    wire                    ch0_enc_bit_out;

    // Channel 0 encoding layer (pins_in[0] - SPI MOSI/MISO)
    encoding_layer #(.CNT_W(CNT_W)) u_enc0 (
        .clk(clk),
        .rst_n(rst_n),
        .mode(enc_mode_ch0),
        .bit_in(pins_in[0]),
        .bit_valid(ch0_ev),
        .bit_out(ch0_enc_bit_out),
        .bit_out_valid(ch0_enc_bit_valid),
        .stuff_after(stuff_after_ch0),
        .stuff_error()
    );

    // Decoded bit streams for protocol detectors
    wire ch0_decoded_a = ch0_enc_bit_out;
    wire ch0_decoded_b = pins_in[1];  // Second pin passes through (SPI SCK)
    wire ch1_decoded_a = pins_in[2];  // I2C SDA - raw
    wire ch1_decoded_b = pins_in[3];  // I2C SCL - raw

    // SPI detector on channel 0
    wire                    spi_frame_valid;
    wire [11:0]             spi_frame_bits;
    wire [7:0]              spi_n_frames;

    spi_detect #(.CNT_W(CNT_W), .IDX_W(IDX_W), .BIN_W(BIN_W)) u_spi (
        .clk(clk), .rst_n(rst_n),
        .pin_a(ch0_decoded_a), .pin_b(ch0_decoded_b), .cs_n(pins_in[4]),
        .hist_ev(ch0_ev), .hist_interval(ch0_interval), .hist_bucket(ch0_bucket),
        .role_a_is_clk(), .mode(),
        .frame_valid(spi_frame_valid), .frame_bits(spi_frame_bits), .n_frames(spi_n_frames));

    // I2C detector on channel 1 - uses RAW signals directly
    wire                    i2c_frame_valid;
    wire [7:0]              i2c_addr;
    wire                    i2c_ack, i2c_is_read;
    wire [7:0]              i2c_n_frames;

    i2c_detect #(.CNT_W(CNT_W)) u_i2c (
        .clk(clk), .rst_n(rst_n),
        .sda(ch1_decoded_a), .scl(ch1_decoded_b),
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
        .match_len(),
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

    // Latch top-ranked result (rank 0) for compilation
    reg [3:0]  top_proto;
    reg [7:0]  top_conf;
    reg [7:0]  top_frame_len;
    reg [31:0] top_frame_data;
    reg        have_top_result;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            have_top_result <= 1'b0;
            top_proto <= 4'd0;
            top_conf <= 8'd0;
            top_frame_len <= 8'd0;
            top_frame_data <= 32'd0;
        end else begin
            if (result_valid && result_rank == 0) begin
                top_proto <= result_proto;
                top_conf <= result_conf;
                top_frame_len <= frame_len_reg;
                top_frame_data <= frame_data_reg;
                have_top_result <= 1'b1;
            end
        end
    end

    // Sequencer compiler - compiles top-ranked result into program
    wire                    compiler_done;
    wire                    compiler_error;
    wire [7:0]              compiler_prog_len;
    reg [7:0]               compiler_rd_addr;
    wire [PROG_W-1:0]       compiler_rd_data;
    reg                     compiler_rd_en;

    // Trigger compiler when we have top result and list is done
    sequencer_compiler #(
        .PROG_DEPTH(PROG_DEPTH),
        .PROG_W(PROG_W)
    ) u_compiler (
        .clk(clk), .rst_n(rst_n),
        .start(list_done && have_top_result),
        .proto_id(top_proto),
        .proto_param(8'd0),
        .frame_len(top_frame_len),
        .frame_data(top_frame_data),
        .done(compiler_done),
        .error(compiler_error),
        .prog_len(compiler_prog_len),
        .prog_rd_addr(compiler_rd_addr),
        .prog_rd_data(compiler_rd_data)
    );

    // Program memory for sequencer (loaded from compiler via read port)
    reg [PROG_W-1:0] prog_mem [0:PROG_DEPTH-1];
    reg [7:0] prog_len_reg;
    reg prog_loaded;
    reg [7:0] load_idx;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prog_len_reg <= 8'd0;
            prog_loaded <= 1'b0;
            load_idx <= 8'd0;
            compiler_rd_addr <= 8'd0;
            compiler_rd_en <= 1'b0;
        end else begin
            if (compiler_done && !prog_loaded) begin
                prog_len_reg <= compiler_prog_len;
                load_idx <= 8'd0;
                compiler_rd_addr <= 8'd0;
                compiler_rd_en <= 1'b1;
            end else if (compiler_rd_en) begin
                prog_mem[load_idx] <= compiler_rd_data;
                if (load_idx == prog_len_reg - 1) begin
                    prog_loaded <= 1'b1;
                    compiler_rd_en <= 1'b0;
                end else begin
                    load_idx <= load_idx + 1'b1;
                    compiler_rd_addr <= compiler_rd_addr + 1'b1;
                end
            end
        end
    end

    // Program data output for sequencer (combinational read - zero latency)
    wire [7:0] seq_prog_addr;
    wire [PROG_W-1:0] seq_prog_data;
    assign seq_prog_data = prog_mem[seq_prog_addr];

    // Sequencer - replays the compiled program
    wire [NUM_PINS-1:0] seq_pins;

    pdis_sequencer #(
        .PROG_DEPTH(PROG_DEPTH),
        .PROG_W(PROG_W),
        .NUM_PINS(NUM_PINS)
    ) u_seq (
        .clk(clk), .rst_n(rst_n),
        .prog_addr(seq_prog_addr),
        .prog_data(seq_prog_data),
        .prog_valid(prog_loaded),
        .pins(seq_pins),
        .start(replay_start && prog_loaded),
        .done(replay_done),
        .error(replay_error),
        .pc(seq_pc),
        .prog_len(prog_len_reg)
    );

    assign prog_len = prog_len_reg;

endmodule
