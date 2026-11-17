/*
 * prog_ram: Loadable program memory for sequencer.
 * 256 x 32-bit words. Loaded via host interface (SPI/I2C/UART).
 * Dual-port: Port A (host write), Port B (sequencer read).
 */
module prog_ram #(
    parameter DEPTH = 256,
    parameter WIDTH = 32,
    parameter ADDR_W = 8
) (
    input  wire                    clk,
    input  wire                    rst_n,
    // Host write port
    input  wire                    host_wr_en,
    input  wire [ADDR_W-1:0]       host_wr_addr,
    input  wire [WIDTH-1:0]        host_wr_data,
    // Sequencer read port
    input  wire [ADDR_W-1:0]       seq_rd_addr,
    output reg  [WIDTH-1:0]        seq_rd_data
);

    reg [WIDTH-1:0] mem [0:DEPTH-1];

    // Host write (async to sequencer read)
    always @(posedge clk) begin
        if (host_wr_en) begin
            mem[host_wr_addr] <= host_wr_data;
        end
    end

    // Sequencer read (combinational - zero latency)
    always @(*) begin
        seq_rd_data = mem[seq_rd_addr];
    end

    // Initialize to NOP
    initial begin
        integer i;
        for (i = 0; i < DEPTH; i = i + 1) begin
            mem[i] = {4'd0, 28'd0}; // OP_NOP
        end
    end

endmodule
