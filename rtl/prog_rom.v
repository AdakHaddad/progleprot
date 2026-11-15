// prog_rom: Simple program ROM for sequencer.
module prog_rom #(
    parameter PROG_DEPTH = 256,
    parameter PROG_W = 32,
    parameter INIT_FILE = ""
) (
    input  wire                    clk,
    input  wire [7:0]              addr,
    output reg [PROG_W-1:0]        data
);

    reg [PROG_W-1:0] mem [0:PROG_DEPTH-1];

    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end else begin
            for (integer i = 0; i < PROG_DEPTH; i = i + 1) mem[i] = {PROG_W{1'b0}};
        end
    end

    always @(posedge clk) begin
        data <= mem[addr];
    end
endmodule
