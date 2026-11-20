`timescale 1ns/1ps

// edge_interval: measures clock cycles between successive edges of one input.
// interval_cycles = N means the two edges were N clk cycles apart.
// If no edge arrives for 2^CNT_W-1 cycles, `idle` pulses once (idle gap / frame boundary hint).
// `level` outputs the synchronized signal level (after 2-flop sync).
module edge_interval #(
    parameter CNT_W = 16
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             signal_in,
    output reg              event_valid,      // 1-cycle pulse per measured interval
    output reg  [CNT_W-1:0] interval_cycles,
    output reg              idle,             // 1-cycle pulse when counter saturates
    output reg              level             // synchronized signal level
);
    localparam [CNT_W-1:0] CNT_MAX = {CNT_W{1'b1}};

    reg sync_q, sync_qq, prev;
    reg [CNT_W-1:0] cnt;
    reg seen_edge;
    wire edge_det = (sync_qq != prev);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_q <= 1'b0; sync_qq <= 1'b0; prev <= 1'b0;
            cnt <= {CNT_W{1'b0}};
            seen_edge <= 1'b0;
            event_valid <= 1'b0;
            interval_cycles <= {CNT_W{1'b0}};
            idle <= 1'b0;
            level <= 1'b0;
        end else begin
            // two-flop synchronizer, then one more stage for edge detection
            sync_q  <= signal_in;
            sync_qq <= sync_q;
            prev    <= sync_qq;

            event_valid <= 1'b0;
            idle        <= 1'b0;
            level       <= sync_qq;

            if (edge_det) begin
                if (seen_edge) begin
                    interval_cycles <= cnt;
                    event_valid     <= 1'b1;
                end
                seen_edge <= 1'b1;
                cnt       <= {{(CNT_W-1){1'b0}}, 1'b1};
            end else if (cnt != CNT_MAX) begin
                cnt <= cnt + 1'b1;
                if (cnt == CNT_MAX - 1'b1) begin
                    idle      <= 1'b1;
                    seen_edge <= 1'b0; // after an idle gap, the next edge starts a new measurement
                end
            end
        end
    end
endmodule
