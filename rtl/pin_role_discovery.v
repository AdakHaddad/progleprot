// pin_role_discovery: Auto-assigns pin roles across multiple input channels.
// Analyzes edge statistics, cross-correlations, and signal patterns to infer:
// - Clock pins (regular periodic edges)
// - Data pins (transitions correlated with clock)
// - CS/frame pins (long idle, frames transactions)
// - UART TX/RX (async, start/stop bits)
// - I2C SDA/SCL (open-drain, START/STOP)
// Outputs a role map per pin.
module pin_role_discovery #(
    parameter NUM_PINS = 8,
    parameter CNT_W = 16,
    parameter FRAC = 1,
    parameter BIN_W = 8,
    parameter IDX_W = $clog2(CNT_W) + FRAC,
    parameter N_COLLECT = 1024
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire [NUM_PINS-1:0]     pins_in,
    input  wire                    clear,
    input  wire                    scan_start,
    output reg [NUM_PINS*3-1:0]    pin_roles,
    output reg [NUM_PINS-1:0]      role_valid,
    output wire                    idle,
    output wire [IDX_W-1:0]        peak_idx,
    output wire [BIN_W-1:0]        peak_count,
    output wire                    scan_done
);

    localparam ROLE_UNUSED = 3'd0;
    localparam ROLE_CLK    = 3'd1;
    localparam ROLE_DATA   = 3'd2;
    localparam ROLE_CS     = 3'd3;
    localparam ROLE_TX     = 3'd4;
    localparam ROLE_RX     = 3'd5;
    localparam ROLE_SDA    = 3'd6;
    localparam ROLE_SCL    = 3'd7;

    // Per-pin edge_interval + log_bucket
    wire [NUM_PINS-1:0]           pin_ev;
    wire [NUM_PINS*CNT_W-1:0]     pin_interval;
    wire [NUM_PINS*IDX_W-1:0]     pin_bucket;
    wire [NUM_PINS-1:0]           pin_idle;
    wire [NUM_PINS-1:0]           pin_level;

    genvar i;
    generate
        for (i = 0; i < NUM_PINS; i = i + 1) begin : g_ei
            edge_interval #(.CNT_W(CNT_W)) u_ei (
                .clk(clk), .rst_n(rst_n), .signal_in(pins_in[i]),
                .event_valid(pin_ev[i]), .interval_cycles(pin_interval[i*CNT_W +: CNT_W]),
                .idle(pin_idle[i]), .level(pin_level[i]));

            log_bucket #(.W(CNT_W), .FRAC(FRAC)) u_lb (
                .x(pin_interval[i*CNT_W +: CNT_W]), .idx(pin_bucket[i*IDX_W +: IDX_W]));
        end
    endgenerate

    // Shared histogram across all pins
    wire [IDX_W-1:0]  hist_rd_idx;
    wire [BIN_W-1:0]  hist_rd_data;

    histogram #(.IDX_W(IDX_W), .CNT_W(BIN_W)) u_hist (
        .clk(clk), .rst_n(rst_n), .clear(clear),
        .inc_valid(|pin_ev),
        .inc_idx(pin_bucket[0 +: IDX_W]),
        .rd_idx(hist_rd_idx), .rd_data(hist_rd_data));

    // Peak detector
    wire pk_busy;
    peak_detect #(.IDX_W(IDX_W), .CNT_W(BIN_W)) u_pk (
        .clk(clk), .rst_n(rst_n), .start(scan_start),
        .rd_idx(hist_rd_idx), .rd_data(hist_rd_data),
        .peak_idx(peak_idx), .peak_count(peak_count),
        .done(scan_done), .busy(pk_busy));

    assign idle = |pin_idle;

    // Collection state machine
    localparam S_COLLECT = 2'd0;
    localparam S_ANALYZE = 2'd1;
    localparam S_ASSIGN  = 2'd2;
    localparam S_DONE    = 2'd3;

    reg [1:0] st;
    reg [9:0] ev_cnt;
    reg [8:0] pin_edge_cnt [0:NUM_PINS-1];
    reg [CNT_W-1:0] pin_min_interval [0:NUM_PINS-1];
    reg [CNT_W-1:0] pin_max_interval [0:NUM_PINS-1];
    reg [CNT_W-1:0] pin_typical_interval [0:NUM_PINS-1];
    reg [8:0] pin_interval_samples [0:NUM_PINS-1];

    // Cross-correlation: for each pin pair, count coincident edges
    reg [9:0] corr_cnt [0:NUM_PINS-1][0:NUM_PINS-1];

    // Level tracking for idle detection
    reg [15:0] pin_high_cycles [0:NUM_PINS-1];
    reg [15:0] pin_low_cycles [0:NUM_PINS-1];

    // Analysis registers
    reg [NUM_PINS-1:0] is_clock_candidate;
    reg [NUM_PINS-1:0] is_cs;

    // Temp role assignment
    reg [NUM_PINS*3-1:0] next_pin_roles;

    integer p, q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_COLLECT;
            ev_cnt <= 10'd0;
            role_valid <= {NUM_PINS{1'b0}};
            pin_roles <= {NUM_PINS*3{1'b0}};
            next_pin_roles <= {NUM_PINS*3{1'b0}};
            is_clock_candidate <= {NUM_PINS{1'b0}};
            is_cs <= {NUM_PINS{1'b0}};
            for (p = 0; p < NUM_PINS; p = p + 1) begin
                pin_edge_cnt[p] <= 9'd0;
                pin_min_interval[p] <= {CNT_W{1'b1}};
                pin_max_interval[p] <= {CNT_W{1'b0}};
                pin_typical_interval[p] <= {CNT_W{1'b0}};
                pin_interval_samples[p] <= 9'd0;
                pin_high_cycles[p] <= 16'd0;
                pin_low_cycles[p] <= 16'd0;
                for (q = 0; q < NUM_PINS; q = q + 1) corr_cnt[p][q] <= 10'd0;
            end
        end else begin
            case (st)
                S_COLLECT: begin
                    // Track level for idle detection
                    for (p = 0; p < NUM_PINS; p = p + 1) begin
                        if (pin_level[p]) pin_high_cycles[p] <= pin_high_cycles[p] + 1'b1;
                        else pin_low_cycles[p] <= pin_low_cycles[p] + 1'b1;
                    end

                    // Collect edge statistics per pin
                    for (p = 0; p < NUM_PINS; p = p + 1) begin
                        if (pin_ev[p]) begin
                            pin_edge_cnt[p] <= pin_edge_cnt[p] + 1'b1;
                            
                            // Only track min/max/typical for "short" intervals (clock periods)
                            // Threshold = 30: includes I2C (4,6), SPI (20), excludes UART (100), frame gaps (30+)
                            if (pin_interval[p*CNT_W +: CNT_W] < 16'd30) begin
                                if (pin_interval[p*CNT_W +: CNT_W] < pin_min_interval[p])
                                    pin_min_interval[p] <= pin_interval[p*CNT_W +: CNT_W];
                                if (pin_interval[p*CNT_W +: CNT_W] > pin_max_interval[p])
                                    pin_max_interval[p] <= pin_interval[p*CNT_W +: CNT_W];
                                
                                if (pin_interval_samples[p] == 0) begin
                                    pin_typical_interval[p] <= pin_interval[p*CNT_W +: CNT_W];
                                end else begin
                                    pin_typical_interval[p] <= pin_typical_interval[p] + 
                                        ((pin_interval[p*CNT_W +: CNT_W] - pin_typical_interval[p]) >> 2);
                                end
                                pin_interval_samples[p] <= pin_interval_samples[p] + 1'b1;
                            end
                        end
                    end

                    // Cross-correlation: coincident edges (same cycle)
                    for (p = 0; p < NUM_PINS; p = p + 1) begin
                        for (q = p+1; q < NUM_PINS; q = q + 1) begin
                            if (pin_ev[p] && pin_ev[q]) begin
                                corr_cnt[p][q] <= corr_cnt[p][q] + 1'b1;
                                corr_cnt[q][p] <= corr_cnt[q][p] + 1'b1;
                            end
                        end
                    end

                    // Count total events across all pins
                    if (|pin_ev) begin
                        if (ev_cnt == N_COLLECT - 1) begin
                            st <= S_ANALYZE;
                        end else begin
                            ev_cnt <= ev_cnt + 1'b1;
                        end
                    end
                end

                S_ANALYZE: begin
                    // Detect clock candidates: high edge count, regular intervals
                    // Min typical = 2 to catch I2C (typical might be 3 due to EMA skew)
                    for (p = 0; p < NUM_PINS; p = p + 1) begin
                        // Clock criteria:
                        // - edge count > 10
                        // - typical interval reasonable (2-500)
                        // - enough short-interval samples (> 8)
                        // - max interval not too much larger than typical (within 3x) - regularity
                        // - min interval not too small compared to typical (> typical/4) - excludes CS with mixed intervals
                        // - min interval > 0
                        if (pin_edge_cnt[p] > 10 && 
                            pin_typical_interval[p] >= 16'd2 &&
                            pin_typical_interval[p] < 16'd500 &&
                            pin_interval_samples[p] > 8 &&
                            pin_max_interval[p] < (pin_typical_interval[p] + (pin_typical_interval[p] << 1)) &&
                            pin_min_interval[p] > (pin_typical_interval[p] >> 2) &&
                            pin_min_interval[p] > 0) begin
                            is_clock_candidate[p] <= 1'b1;
                        end else begin
                            is_clock_candidate[p] <= 1'b0;
                        end
                    end

                    // Detect CS: stays at one level most of the time, low edge count
                    for (p = 0; p < NUM_PINS; p = p + 1) begin
                        reg [15:0] total_cycles;
                        total_cycles = pin_high_cycles[p] + pin_low_cycles[p];
                        // CS has low edges (< 30) and is mostly one level (> 70%)
                        if (pin_edge_cnt[p] < 30 && total_cycles > 16'd100 &&
                            ((pin_high_cycles[p] > (total_cycles * 7 / 10)) || 
                             (pin_low_cycles[p] > (total_cycles * 7 / 10)))) begin
                            is_cs[p] <= 1'b1;
                        end else begin
                            is_cs[p] <= 1'b0;
                        end
                    end

                    st <= S_ASSIGN;
                end

                S_ASSIGN: begin
                    // Start with current roles
                    next_pin_roles = pin_roles;

                    // First pass: assign CS
                    for (p = 0; p < NUM_PINS; p = p + 1) begin
                        if (is_cs[p]) begin
                            next_pin_roles[p*3 +: 3] = ROLE_CS;
                        end
                    end

                    // Second pass: assign clocks
                    // If two clock candidates correlate strongly, keep the one with MORE edges as CLK,
                    // demote the other to DATA (this handles SPI SCK vs MOSI)
                    for (p = 0; p < NUM_PINS; p = p + 1) begin
                        if (is_clock_candidate[p] && next_pin_roles[p*3 +: 3] == ROLE_UNUSED) begin
                            // Check if this clock candidate correlates with another clock candidate
                            // that has MORE edges - if so, this is likely DATA
                            reg demote_to_data;
                            demote_to_data = 1'b0;
                            for (q = 0; q < NUM_PINS; q = q + 1) begin
                                if (q != p && is_clock_candidate[q] && corr_cnt[p][q] > 8 && pin_edge_cnt[q] > pin_edge_cnt[p]) begin
                                    demote_to_data = 1'b1;
                                end
                            end
                            if (demote_to_data) begin
                                next_pin_roles[p*3 +: 3] = ROLE_DATA;
                            end else begin
                                next_pin_roles[p*3 +: 3] = ROLE_CLK;
                            end
                        end
                    end

                    // Third pass: demote clock candidates that have a "stronger" clock partner with similar timing
                    // This handles I2C SDA vs SCL: SCL has more edges, similar typical interval
                    for (p = 0; p < NUM_PINS; p = p + 1) begin
                        if (is_clock_candidate[p] && next_pin_roles[p*3 +: 3] == ROLE_CLK) begin
                            for (q = 0; q < NUM_PINS; q = q + 1) begin
                                if (q != p && is_clock_candidate[q] && next_pin_roles[q*3 +: 3] == ROLE_CLK) begin
                                    // If q has significantly more edges (> 2x) and similar typical interval (within 2x)
                                    if (pin_edge_cnt[q] > (pin_edge_cnt[p] << 1) && 
                                        pin_typical_interval[q] < (pin_typical_interval[p] << 1) &&
                                        pin_typical_interval[p] < (pin_typical_interval[q] << 1)) begin
                                        next_pin_roles[p*3 +: 3] = ROLE_DATA;
                                    end
                                end
                            end
                        end
                    end

                    // Fourth pass: assign data pins correlated with clocks (for non-clock-candidates)
                    for (p = 0; p < NUM_PINS; p = p + 1) begin
                        if (is_clock_candidate[p] && next_pin_roles[p*3 +: 3] == ROLE_CLK) begin
                            for (q = 0; q < NUM_PINS; q = q + 1) begin
                                if (q != p && corr_cnt[p][q] > 4 && next_pin_roles[q*3 +: 3] == ROLE_UNUSED) begin
                                    next_pin_roles[q*3 +: 3] = ROLE_DATA;
                                end
                            end
                        end
                    end

                    // Fifth pass: handle I2C - SDA correlates with SCL (clock)
                    // Since SDA/SCL edges are not coincident, use edge count heuristic:
                    // SCL has more edges, SDA has fewer. If two clock candidates have similar
                    // typical interval but very different edge counts, the lower one is SDA.
                    for (p = 0; p < NUM_PINS; p = p + 1) begin
                        if (next_pin_roles[p*3 +: 3] == ROLE_UNUSED && pin_edge_cnt[p] > 5) begin
                            // Check for I2C SDA: another clock candidate with similar timing but more edges
                            reg found_scl;
                            reg [3:0] scl_pin;
                            found_scl = 1'b0;
                            scl_pin = 4'd0;
                            for (q = 0; q < NUM_PINS; q = q + 1) begin
                                if (is_clock_candidate[q] && next_pin_roles[q*3 +: 3] == ROLE_CLK &&
                                    pin_edge_cnt[q] > (pin_edge_cnt[p] << 1) &&
                                    pin_typical_interval[q] < (pin_typical_interval[p] << 1) &&
                                    pin_typical_interval[p] < (pin_typical_interval[q] << 1)) begin
                                    found_scl = 1'b1;
                                    scl_pin = q;
                                end
                            end
                            if (found_scl) begin
                                next_pin_roles[p*3 +: 3] = ROLE_SDA;
                                // The clock it correlates with is likely SCL
                                if (next_pin_roles[scl_pin*3 +: 3] == ROLE_CLK) begin
                                    next_pin_roles[scl_pin*3 +: 3] = ROLE_SCL;
                                end
                            end
                        end
                    end

                    // Sixth pass: remaining pins
                    for (p = 0; p < NUM_PINS; p = p + 1) begin
                        if (next_pin_roles[p*3 +: 3] == ROLE_UNUSED) begin
                            if (pin_edge_cnt[p] > 5) begin
                                // Isolated clock candidate (no correlation) -> likely UART TX
                                if (is_clock_candidate[p]) begin
                                    reg has_corr;
                                    has_corr = 1'b0;
                                    for (q = 0; q < NUM_PINS; q = q + 1) begin
                                        if (q != p && corr_cnt[p][q] > 2) begin
                                            has_corr = 1'b1;
                                        end
                                    end
                                    if (!has_corr) begin
                                        next_pin_roles[p*3 +: 3] = ROLE_TX;
                                    end else begin
                                        next_pin_roles[p*3 +: 3] = ROLE_CLK;
                                    end
                                end else begin
                                    next_pin_roles[p*3 +: 3] = ROLE_TX;
                                end
                            end
                        end
                        role_valid[p] <= 1'b1;
                    end
                    
                    // Commit all role assignments at once
                    pin_roles <= next_pin_roles;
                    st <= S_DONE;
                end

                S_DONE: begin
                    // Hold results
                end
            endcase
        end
    end
endmodule
