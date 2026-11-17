// histogram: saturating counters, one per bucket, plus a clear and a read port.
// NOTE: flop-based. Area is N_BINS*CNT_W flops; consider an SRAM macro later.
module histogram #(
    parameter IDX_W = 6,
    parameter CNT_W = 12
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             clear,       // synchronous clear of all cnt_mem
    input  wire             inc_valid,
    input  wire [IDX_W-1:0] inc_idx,
    input  wire [IDX_W-1:0] rd_idx,
    output wire [CNT_W-1:0] rd_data
);
    localparam N = 1 << IDX_W;
    localparam [CNT_W-1:0] SAT = {CNT_W{1'b1}};
    reg [CNT_W-1:0] cnt_mem [0:N-1];
    integer i;

    assign rd_data = cnt_mem[rd_idx];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < N; i = i + 1) cnt_mem[i] <= {CNT_W{1'b0}};
        end else if (clear) begin
            for (i = 0; i < N; i = i + 1) cnt_mem[i] <= {CNT_W{1'b0}};
        end else if (inc_valid && cnt_mem[inc_idx] != SAT) begin
            cnt_mem[inc_idx] <= cnt_mem[inc_idx] + 1'b1;
        end
    end
endmodule
