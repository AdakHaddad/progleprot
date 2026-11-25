/*
 * Simple behavioral SRAM model for simulation
 * Replaces IHP RM_IHPSG13_1P_1024x16_c2_bm_bist for sim
 */
`timescale 1ns/1ps

module SRAM_1P_behavioral_bm_bist #(
    parameter P_DATA_WIDTH = 16,
    parameter P_ADDR_WIDTH = 10
) (
    input  wire                    A_CLK,
    input  wire                    A_MEN,
    input  wire                    A_WEN,
    input  wire                    A_REN,
    input  wire [P_ADDR_WIDTH-1:0] A_ADDR,
    input  wire                    A_DLY,
    input  wire [P_DATA_WIDTH-1:0] A_DIN,
    output reg  [P_DATA_WIDTH-1:0] A_DOUT,
    input  wire [P_DATA_WIDTH-1:0] A_BM,
    input  wire                    A_BIST_CLK,
    input  wire                    A_BIST_EN,
    input  wire                    A_BIST_MEN,
    input  wire                    A_BIST_WEN,
    input  wire                    A_BIST_REN,
    input  wire [P_ADDR_WIDTH-1:0] A_BIST_ADDR,
    input  wire [P_DATA_WIDTH-1:0] A_BIST_DIN,
    input  wire [P_DATA_WIDTH-1:0] A_BIST_BM
);

    reg [P_DATA_WIDTH-1:0] mem [0:(1<<P_ADDR_WIDTH)-1];
    integer i;

    initial begin
        for (i = 0; i < (1<<P_ADDR_WIDTH); i = i + 1)
            mem[i] = {P_DATA_WIDTH{1'b0}};
    end

    always @(posedge A_CLK) begin
        if (A_MEN) begin
            if (A_WEN) begin
                mem[A_ADDR] <= (mem[A_ADDR] & ~A_BM) | (A_DIN & A_BM);
            end
            if (A_REN) begin
                A_DOUT <= mem[A_ADDR];
            end
        end
    end

    // BIST support (simplified)
    always @(posedge A_BIST_CLK) begin
        if (A_BIST_EN && A_BIST_MEN) begin
            if (A_BIST_WEN) begin
                mem[A_BIST_ADDR] <= (mem[A_BIST_ADDR] & ~A_BIST_BM) | (A_BIST_DIN & A_BIST_BM);
            end
            if (A_BIST_REN) begin
                A_DOUT <= mem[A_BIST_ADDR];
            end
        end
    end

endmodule

// Wrapper for IHP SRAM macro
module RM_IHPSG13_1P_1024x16_c2_bm_bist (
    input  wire         A_CLK,
    input  wire         A_MEN,
    input  wire         A_WEN,
    input  wire         A_REN,
    input  wire [9:0]   A_ADDR,
    input  wire [15:0]  A_DIN,
    input  wire         A_DLY,
    output wire [15:0]  A_DOUT,
    input  wire [15:0]  A_BM,
    input  wire         A_BIST_CLK,
    input  wire         A_BIST_EN,
    input  wire         A_BIST_MEN,
    input  wire         A_BIST_WEN,
    input  wire         A_BIST_REN,
    input  wire [9:0]   A_BIST_ADDR,
    input  wire [15:0]  A_BIST_DIN,
    input  wire [15:0]  A_BIST_BM
);

    SRAM_1P_behavioral_bm_bist #(
        .P_DATA_WIDTH(16),
        .P_ADDR_WIDTH(10)
    ) i_sram (
        .A_CLK(A_CLK),
        .A_MEN(A_MEN),
        .A_WEN(A_WEN),
        .A_REN(A_REN),
        .A_ADDR(A_ADDR),
        .A_DLY(A_DLY),
        .A_DIN(A_DIN),
        .A_DOUT(A_DOUT),
        .A_BM(A_BM),
        .A_BIST_CLK(A_BIST_CLK),
        .A_BIST_EN(A_BIST_EN),
        .A_BIST_MEN(A_BIST_MEN),
        .A_BIST_WEN(A_BIST_WEN),
        .A_BIST_REN(A_BIST_REN),
        .A_BIST_ADDR(A_BIST_ADDR),
        .A_BIST_DIN(A_BIST_DIN),
        .A_BIST_BM(A_BIST_BM)
    );

endmodule
