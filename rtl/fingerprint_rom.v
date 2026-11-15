// fingerprint_rom: Stores known protocol signatures for fast matching.
// Each fingerprint: {protocol_id[3:0], pattern_len[7:0], pattern[255:0] (variable)}
// Protocols: 0=UART, 1=SPI, 2=I2C, 3=JTAG, 4=SWD, 5=PS2, 6=CAN, 7=USB-LS
module fingerprint_rom #(
    parameter NUM_PRINTS = 16,
    parameter MAX_PATTERN_BITS = 64
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire [$clog2(NUM_PRINTS)-1:0]  rd_addr,
    output reg [3:0]               proto_id,
    output reg [7:0]               pattern_len,
    output reg [MAX_PATTERN_BITS-1:0] pattern
);
    // ROM contents - initialized with known protocol signatures
    // Format: {proto_id, pattern_len, pattern_bits}
    reg [3:0] rom_proto [0:NUM_PRINTS-1];
    reg [7:0] rom_len   [0:NUM_PRINTS-1];
    reg [MAX_PATTERN_BITS-1:0] rom_pat [0:NUM_PRINTS-1];

    initial begin
        // UART fingerprints (proto_id = 0)
        rom_proto[0] = 4'd0; rom_len[0] = 8'd10; rom_pat[0] = 64'b1_01010101_0;  // 8N1: start=0, 0x55, stop=1
        rom_proto[1] = 4'd0; rom_len[1] = 8'd10; rom_pat[1] = 64'b1_00110011_0;  // 8N1: start=0, 0x33, stop=1
        rom_proto[2] = 4'd0; rom_len[2] = 8'd11; rom_pat[2] = 64'b1_01010101_01; // 8E1: start=0, 0x55, parity=0, stop=1
        rom_proto[3] = 4'd0; rom_len[3] = 8'd11; rom_pat[3] = 64'b1_01010101_11; // 8O1: start=0, 0x55, parity=1, stop=1

        // SPI fingerprints (proto_id = 1) - clock/idle patterns
        rom_proto[4] = 4'd1; rom_len[4] = 8'd8;  rom_pat[4] = 64'h00;  // SPI mode 0: CPOL=0, CPHA=0 (clock idle low)
        rom_proto[5] = 4'd1; rom_len[5] = 8'd8;  rom_pat[5] = 64'hFF;  // SPI mode 1: CPOL=1, CPHA=0 (clock idle high)
        rom_proto[6] = 4'd1; rom_len[6] = 8'd8;  rom_pat[6] = 64'hAA;  // SPI mode 2: CPOL=0, CPHA=1
        rom_proto[7] = 4'd1; rom_len[7] = 8'd8;  rom_pat[7] = 64'h55;  // SPI mode 3: CPOL=1, CPHA=1

        // I2C fingerprints (proto_id = 2)
        rom_proto[8]  = 4'd2; rom_len[8]  = 8'd16; rom_pat[8]  = 64'b11111111_00000000;  // START + addr(0x00) + W + ACK
        rom_proto[9]  = 4'd2; rom_len[9]  = 8'd16; rom_pat[9]  = 64'b11111111_01010000;  // START + addr(0x50) + W + ACK
        rom_proto[10] = 4'd2; rom_len[10] = 8'd16; rom_pat[10] = 64'b11111111_01010001;  // START + addr(0x50) + R + ACK

        // JTAG/SWD fingerprints (proto_id = 3, 4)
        rom_proto[11] = 4'd3; rom_len[11] = 8'd32; rom_pat[11] = 64'hE79E;  // JTAG reset sequence (5 TMS=1)
        rom_proto[12] = 4'd4; rom_len[12] = 8'd16; rom_pat[12] = 64'h0000;  // SWD read DPIDR

        // PS/2 fingerprints (proto_id = 5)
        rom_proto[13] = 4'd5; rom_len[13] = 8'd11; rom_pat[13] = 64'b1_01000000_11; // PS/2: start=0, data, parity=1, stop=1

        // CAN fingerprints (proto_id = 6)
        rom_proto[14] = 4'd6; rom_len[14] = 8'd11; rom_pat[14] = 64'b0_11111111111;  // CAN SOF + 11-bit ID all recessive

        // USB-LS fingerprints (proto_id = 7)
        rom_proto[15] = 4'd7; rom_len[15] = 8'd8;  rom_pat[15] = 64'h80;  // USB LS SYNC (K-J-K-J-K-J-K-K)
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            proto_id <= 4'd0;
            pattern_len <= 8'd0;
            pattern <= {MAX_PATTERN_BITS{1'b0}};
        end else begin
            proto_id <= rom_proto[rd_addr];
            pattern_len <= rom_len[rd_addr];
            pattern <= rom_pat[rd_addr];
        end
    end
endmodule
