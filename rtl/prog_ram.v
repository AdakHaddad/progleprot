/*
 * prog_ram: Dual-port program memory with block RAM inference.
 * Supports configurable width/depth for both 16-bit (CPU) and 32-bit (sequencer) archs.
 * Uses ram_style attribute for block RAM inference in synthesis.
 */
module prog_ram #(
    parameter DEPTH = 2048,
    parameter WIDTH = 16,
    parameter ADDR_W = 11
) (
    input  wire                    clk,
    input  wire                    rst_n,
    // Host write port
    input  wire                    host_wr_en,
    input  wire [ADDR_W-1:0]       host_wr_addr,
    input  wire [WIDTH-1:0]        host_wr_data,
    // CPU/Sequencer read port
    input  wire [ADDR_W-1:0]       seq_rd_addr,
    output reg  [WIDTH-1:0]        seq_rd_data
);

    (* ram_style = "block" *)
    reg [WIDTH-1:0] mem [0:DEPTH-1];

    // Host write (synchronous)
    always @(posedge clk) begin
        if (host_wr_en) begin
            mem[host_wr_addr] <= host_wr_data;
        end
    end

    // Sequencer read (registered - 1 cycle latency for block RAM)
    always @(posedge clk) begin
        seq_rd_data <= mem[seq_rd_addr];
    end

    // Initialize to NOP (0x0000 for 16-bit, or OP_NOP for 32-bit)
    initial begin
        integer i;
        for (i = 0; i < DEPTH; i = i + 1) begin
            mem[i] = {WIDTH{1'b0}};
        end
    end

endmodule
