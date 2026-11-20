// peak_detect: on `start`, scans all bins once and reports the bin with the largest count.
// Ties keep the lowest index. `done` pulses when peak_idx/peak_count are valid.
module peak_detect #(
    parameter IDX_W = 6,
    parameter CNT_W = 12
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             start,
    output reg  [IDX_W-1:0] rd_idx,
    input  wire [CNT_W-1:0] rd_data,
    output reg  [IDX_W-1:0] peak_idx,
    output reg  [CNT_W-1:0] peak_count,
    output reg              done,
    output reg              busy
);
    localparam [IDX_W-1:0] LAST = {IDX_W{1'b1}};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_idx <= 0; peak_idx <= 0; peak_count <= 0;
            done <= 0; busy <= 0;
        end else begin
            done <= 1'b0;
            if (start && !busy) begin
                busy <= 1'b1; rd_idx <= 0;
                peak_idx <= 0; peak_count <= 0;
            end else if (busy) begin
                // rd_data is combinational on rd_idx, so rd_data matches rd_idx now
                if (rd_data > peak_count) begin
                    peak_count <= rd_data;
                    peak_idx   <= rd_idx;
                end
                if (rd_idx == LAST) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end else begin
                    rd_idx <= rd_idx + 1'b1;
                end
            end
        end
    end
endmodule
