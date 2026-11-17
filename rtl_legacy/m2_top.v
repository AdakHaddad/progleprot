// m2_top: UART auto-baud + frame-format inference.
// Phases: COLLECT (histogram) -> SCAN (peak bucket) -> REFINE (3 passes: bucket mean, then two
// windowed means of 16 intervals within +-25% of the estimate) -> CHECK (subharmonic test: if
// intervals near T/2 are at least half as common as near T, halve T and refine again)
// -> FRAME (score 6 hypotheses over N_FRAMES frames, TOL disagreeing frames allowed) -> DONE.
// Hypotheses: 7N1 7E1 7O1 8N1 8E1 8O1. 2 stop bits are indistinguishable from 1 stop + idle.
// Result: parity 0=none 1=even 2=odd; data8=1 for 8 data bits.
module m2_top #(
    parameter CNT_W     = 16,
    parameter FRAC      = 1,
    parameter BIN_W     = 8,
    parameter N_COLLECT = 64,
    parameter N_REFINE  = 128,  // max events spent per refine pass
    parameter N_CHECK   = 64,   // events observed in the subharmonic check
    parameter N_FRAMES  = 32,
    parameter TOL       = 4     // frames allowed to disagree with the winning hypothesis
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             signal_in,
    output reg              done,
    output reg              fail,
    output reg [CNT_W-1:0]  bit_cycles,
    output reg              data8,
    output reg [1:0]        parity,
    output reg [2:0]        phase,
    output reg [7:0]        n_frames
);
    localparam IDX_W = $clog2(CNT_W) + FRAC;
    localparam PH_COLLECT = 3'd0, PH_SCAN = 3'd1, PH_REFINE = 3'd2, PH_CHECK = 3'd3,
               PH_FRAME = 3'd4, PH_DONE = 3'd5;

    wire              ev, idle, level;
    wire [CNT_W-1:0]  interval;
    wire [IDX_W-1:0]  bucket, rd_idx, peak_idx;
    wire [BIN_W-1:0]  rd_data, peak_count;
    wire              scan_done, pk_busy;
    reg               scan_start;

    edge_interval #(.CNT_W(CNT_W)) u_ei (
        .clk(clk), .rst_n(rst_n), .signal_in(signal_in),
        .event_valid(ev), .interval_cycles(interval), .idle(idle), .level(level));
    log_bucket #(.W(CNT_W), .FRAC(FRAC)) u_lb (.x(interval), .idx(bucket));
    histogram #(.IDX_W(IDX_W), .CNT_W(BIN_W)) u_h (
        .clk(clk), .rst_n(rst_n), .clear(1'b0),
        .inc_valid(ev && phase == PH_COLLECT), .inc_idx(bucket),
        .rd_idx(rd_idx), .rd_data(rd_data));
    peak_detect #(.IDX_W(IDX_W), .CNT_W(BIN_W)) u_pk (
        .clk(clk), .rst_n(rst_n), .start(scan_start),
        .rd_idx(rd_idx), .rd_data(rd_data),
        .peak_idx(peak_idx), .peak_count(peak_count), .done(scan_done), .busy(pk_busy));

    wire        frame_valid;
    wire [9:0]  fbits;
    uart_framer #(.CNT_W(CNT_W)) u_fr (
        .clk(clk), .rst_n(rst_n), .en(phase == PH_FRAME), .sig(level),
        .bit_cycles(bit_cycles), .frame_valid(frame_valid), .bits(fbits));

    // ---- hypothesis checks on one frame: s[k] = slot k, s[0] = start bit ----
    wire [10:0] s  = {fbits, 1'b0};
    wire        p7 = ^s[7:1];
    wire        p8 = ^s[8:1];
    wire [5:0]  ok;
    assign ok[0] = s[8];                         // 7N1
    assign ok[1] = (s[8] == p7)  && s[9];        // 7E1
    assign ok[2] = (s[8] == ~p7) && s[9];        // 7O1
    assign ok[3] = s[9];                         // 8N1
    assign ok[4] = (s[9] == p8)  && s[10];       // 8E1
    assign ok[5] = (s[9] == ~p8) && s[10];       // 8O1

    reg [7:0] cons [0:5];
    wire [5:0] all_ok;
    genvar g;
    generate for (g = 0; g < 6; g = g + 1) begin : g_all
        assign all_ok[g] = ({1'b0, cons[g]} + ok[g]) >= (N_FRAMES - TOL);
    end endgenerate

    // ---- period estimation state ----
    reg [IDX_W-1:0] pk;
    reg [CNT_W-1:0] t1;
    reg [CNT_W+3:0] sum, sum_n;
    reg [4:0]       in_cnt;
    reg [1:0]       pass, halvings;
    reg [7:0]       ev_cnt, c_t, c_h, ct_n, ch_n;
    reg             in_range, complete;

    wire [CNT_W-1:0] t_half = t1 >> 1;
    wire [CNT_W-1:0] d_t    = (interval > t1)     ? interval - t1     : t1 - interval;
    wire [CNT_W-1:0] d_h    = (interval > t_half) ? interval - t_half : t_half - interval;
    wire near_t = (d_t <= (t1 >> 2));
    wire near_h = (d_h <= (t_half >> 2));
    integer h;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done <= 0; fail <= 0; bit_cycles <= 0; data8 <= 0; parity <= 0;
            phase <= PH_COLLECT; n_frames <= 0; scan_start <= 0;
            pk <= 0; t1 <= 0; sum <= 0; in_cnt <= 0; ev_cnt <= 0;
            pass <= 0; halvings <= 0; c_t <= 0; c_h <= 0;
            for (h = 0; h < 6; h = h + 1) cons[h] <= 0;
        end else begin
            scan_start <= 1'b0;
            case (phase)
                PH_COLLECT: if (ev) begin
                    if (ev_cnt == N_COLLECT - 1) begin
                        ev_cnt <= 0; phase <= PH_SCAN; scan_start <= 1'b1;
                    end else ev_cnt <= ev_cnt + 1'b1;
                end
                PH_SCAN: if (scan_done) begin
                    pk <= peak_idx; sum <= 0; in_cnt <= 0; ev_cnt <= 0;
                    pass <= 0; halvings <= 0; phase <= PH_REFINE;
                end
                PH_REFINE: if (ev) begin
                    complete = 1'b0;
                    in_range = (pass == 0) ? (bucket == pk && interval != 0) : near_t;
                    if (in_range) begin
                        sum_n = sum + interval;
                        if (in_cnt == 5'd15) begin
                            t1 <= sum_n >> 4;           // mean of 16 intervals
                            sum <= 0; in_cnt <= 0; ev_cnt <= 0;
                            complete = 1'b1;
                            if (pass == 2'd2) begin
                                c_t <= 0; c_h <= 0; phase <= PH_CHECK;
                            end else pass <= pass + 1'b1;
                        end else begin
                            sum <= sum_n; in_cnt <= in_cnt + 1'b1;
                        end
                    end
                    if (!complete) begin
                        if (ev_cnt == N_REFINE - 1) begin fail <= 1'b1; done <= 1'b1; phase <= PH_DONE; end
                        else ev_cnt <= ev_cnt + 1'b1;
                    end
                end
                PH_CHECK: if (ev) begin
                    ct_n = c_t + near_t;
                    ch_n = c_h + near_h;
                    c_t <= ct_n; c_h <= ch_n;
                    if (ev_cnt == N_CHECK - 1) begin
                        ev_cnt <= 0;
                        if ((ch_n << 1) >= ct_n && ch_n >= 8'd4 && halvings != 2'd2 && t_half >= 4) begin
                            // intervals near T/2 are common: the real bit period is shorter
                            t1 <= t_half; halvings <= halvings + 1'b1;
                            pass <= 2'd1; sum <= 0; in_cnt <= 0; phase <= PH_REFINE;
                        end else begin
                            bit_cycles <= t1; phase <= PH_FRAME;
                        end
                    end else ev_cnt <= ev_cnt + 1'b1;
                end
                PH_FRAME: if (frame_valid) begin
                    for (h = 0; h < 6; h = h + 1) cons[h] <= cons[h] + ok[h];
                    n_frames <= n_frames + 1'b1;
                    if (n_frames == N_FRAMES - 1) begin
                        phase <= PH_DONE; done <= 1'b1;
                        // prefer the shortest consistent frame: a 7E1 frame also passes as 8O1
                        // (stop bit acts as the parity bit), but a true 8-bit frame fails 7-bit checks
                        if      (all_ok[1]) begin data8 <= 0; parity <= 2'd1; end
                        else if (all_ok[2]) begin data8 <= 0; parity <= 2'd2; end
                        else if (all_ok[0]) begin data8 <= 0; parity <= 2'd0; end
                        else if (all_ok[4]) begin data8 <= 1; parity <= 2'd1; end
                        else if (all_ok[5]) begin data8 <= 1; parity <= 2'd2; end
                        else if (all_ok[3]) begin data8 <= 1; parity <= 2'd0; end
                        else fail <= 1'b1;
                    end
                end
                default: ;
            endcase
        end
    end
endmodule
