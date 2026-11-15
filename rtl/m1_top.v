// m1_top: edge_interval -> log_bucket -> histogram, with a peak scanner.
module m1_top #(
    parameter CNT_W  = 16,   // interval counter width
    parameter FRAC   = 1,
    parameter BIN_W  = 8
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               signal_in,
    input  wire               clear,
    input  wire               scan_start,
    output wire               idle,
    output wire [$clog2(CNT_W)+FRAC-1:0] peak_idx,
    output wire [BIN_W-1:0]   peak_count,
    output wire               scan_done
);
    localparam IDX_W = $clog2(CNT_W) + FRAC;

    wire              ev;
    wire [CNT_W-1:0]  interval;
    wire [IDX_W-1:0]  bucket;
    wire [IDX_W-1:0]  rd_idx;
    wire [BIN_W-1:0]  rd_data;
    wire              busy;

    edge_interval #(.CNT_W(CNT_W)) u_ei (
        .clk(clk), .rst_n(rst_n), .signal_in(signal_in),
        .event_valid(ev), .interval_cycles(interval), .idle(idle));

    log_bucket #(.W(CNT_W), .FRAC(FRAC)) u_lb (.x(interval), .idx(bucket));

    histogram #(.IDX_W(IDX_W), .CNT_W(BIN_W)) u_h (
        .clk(clk), .rst_n(rst_n), .clear(clear),
        .inc_valid(ev), .inc_idx(bucket),
        .rd_idx(rd_idx), .rd_data(rd_data));

    peak_detect #(.IDX_W(IDX_W), .CNT_W(BIN_W)) u_pk (
        .clk(clk), .rst_n(rst_n), .start(scan_start),
        .rd_idx(rd_idx), .rd_data(rd_data),
        .peak_idx(peak_idx), .peak_count(peak_count),
        .done(scan_done), .busy(busy));
endmodule
