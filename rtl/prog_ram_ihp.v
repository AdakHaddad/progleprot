/*
 * prog_ram_ihp: Program memory using IHP SG13 1024x16 SRAM macros.
 * Two 1024x16 macros combined for 2048x16 = 4KB program memory.
 * Compatible with IHP-Open-PDK ihp-sg13g2/sg13cmos5l SRAM.
 */
module prog_ram_ihp #(
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
    output wire [WIDTH-1:0]        seq_rd_data
);

    // Split address: MSB selects bank (0 or 1), lower 10 bits for 1024x16
    wire bank_sel_host = host_wr_addr[10];
    wire bank_sel_seq  = seq_rd_addr[10];
    wire [9:0] addr_host = host_wr_addr[9:0];
    wire [9:0] addr_seq  = seq_rd_addr[9:0];

    // Bank 0: addresses 0x000-0x3FF
    wire [WIDTH-1:0] bank0_dout;
    wire bank0_ren = ~host_wr_en | bank_sel_host;  // read when not writing to bank 0
    wire bank0_wen = host_wr_en & ~bank_sel_host;  // write when host writes to bank 0
    RM_IHPSG13_1P_1024x16_c2_bm_bist u_bank0 (
        .A_CLK        (clk),
        .A_MEN        (1'b1),
        .A_WEN        (bank0_wen),
        .A_REN        (bank0_ren),
        .A_ADDR       (bank0_wen ? addr_host : addr_seq),
        .A_DIN        (host_wr_data),
        .A_DLY        (1'b1),
        .A_DOUT       (bank0_dout),
        .A_BM         ({WIDTH{1'b1}}),
        .A_BIST_CLK   (1'b0),
        .A_BIST_EN    (1'b0),
        .A_BIST_MEN   (1'b0),
        .A_BIST_WEN   (1'b0),
        .A_BIST_REN   (1'b0),
        .A_BIST_ADDR  (10'd0),
        .A_BIST_DIN   (16'd0),
        .A_BIST_BM    (16'd0)
    );

    // Bank 1: addresses 0x400-0x7FF
    wire [WIDTH-1:0] bank1_dout;
    wire bank1_ren = ~host_wr_en | ~bank_sel_host;  // read when not writing to bank 1
    wire bank1_wen = host_wr_en & bank_sel_host;    // write when host writes to bank 1
    RM_IHPSG13_1P_1024x16_c2_bm_bist u_bank1 (
        .A_CLK        (clk),
        .A_MEN        (1'b1),
        .A_WEN        (bank1_wen),
        .A_REN        (bank1_ren),
        .A_ADDR       (bank1_wen ? addr_host : addr_seq),
        .A_DIN        (host_wr_data),
        .A_DLY        (1'b1),
        .A_DOUT       (bank1_dout),
        .A_BM         ({WIDTH{1'b1}}),
        .A_BIST_CLK   (1'b0),
        .A_BIST_EN    (1'b0),
        .A_BIST_MEN   (1'b0),
        .A_BIST_WEN   (1'b0),
        .A_BIST_REN   (1'b0),
        .A_BIST_ADDR  (10'd0),
        .A_BIST_DIN   (16'd0),
        .A_BIST_BM    (16'd0)
    );

    // Mux read data based on bank select for sequencer read
    assign seq_rd_data = bank_sel_seq ? bank1_dout : bank0_dout;

endmodule
