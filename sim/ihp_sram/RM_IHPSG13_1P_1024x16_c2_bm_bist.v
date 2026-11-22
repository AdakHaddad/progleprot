/* Simulation behavioral model for IHP SRAM 1024x16 */
`timescale 1ns/10ps
module RM_IHPSG13_1P_1024x16_c2_bm_bist (
    input  wire        A_CLK,
    input  wire        A_MEN,
    input  wire        A_WEN,
    input  wire        A_REN,
    input  wire [9:0]  A_ADDR,
    input  wire [15:0] A_DIN,
    input  wire        A_DLY,
    output reg  [15:0] A_DOUT,
    input  wire [15:0] A_BM,
    input  wire        A_BIST_CLK,
    input  wire        A_BIST_EN,
    input  wire        A_BIST_MEN,
    input  wire        A_BIST_WEN,
    input  wire        A_BIST_REN,
    input  wire [9:0]  A_BIST_ADDR,
    input  wire [15:0] A_BIST_DIN,
    input  wire [15:0] A_BIST_BM
);

    reg [15:0] memory [0:1023];

    // BIST mux
    wire [9:0]  ADDR_MUX = A_BIST_EN ? A_BIST_ADDR : A_ADDR;
    wire [15:0] DIN_MUX  = A_BIST_EN ? A_BIST_DIN : A_DIN;
    wire [15:0] BM_MUX   = A_BIST_EN ? A_BIST_BM : A_BM;
    wire        MEN_MUX  = A_BIST_EN ? A_BIST_MEN : A_MEN;
    wire        WEN_MUX  = A_BIST_EN ? A_BIST_WEN : A_WEN;
    wire        REN_MUX  = A_BIST_EN ? A_BIST_REN : A_REN;
    wire        CLK_MUX  = A_BIST_EN ? A_BIST_CLK : A_CLK;

    always @(posedge CLK_MUX) begin
        if (MEN_MUX && WEN_MUX) begin
            memory[ADDR_MUX] <= (memory[ADDR_MUX] & ~BM_MUX) | (DIN_MUX & BM_MUX);
            if (REN_MUX) begin
                A_DOUT <= (memory[ADDR_MUX] & ~BM_MUX) | (DIN_MUX & BM_MUX);
            end
        end else if (MEN_MUX && REN_MUX) begin
            A_DOUT <= memory[ADDR_MUX];
        end
    end

    // Initialize
    initial begin
        integer i;
        for (i = 0; i < 1024; i = i + 1) begin
            memory[i] = 16'h0000;
        end
        A_DOUT = 16'h0000;
    end

endmodule
