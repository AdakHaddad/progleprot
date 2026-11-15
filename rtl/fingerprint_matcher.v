// fingerprint_matcher: Compares incoming frame against fingerprint ROM.
// Scores each fingerprint by Hamming distance, outputs top matches.
module fingerprint_matcher #(
    parameter NUM_PRINTS = 16,
    parameter MAX_PATTERN_BITS = 64,
    parameter FRAME_BITS = 32
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    frame_valid,
    input  wire [FRAME_BITS-1:0]   frame_data,
    input  wire [7:0]              frame_len,
    input  wire [3:0]              proto_hint,   // optional: restrict to protocol class
    input  wire                    hint_valid,
    output reg                     match_valid,
    output reg [3:0]               match_proto,
    output reg [7:0]               match_score,  // 0=exact, 255=worst (inverted confidence)
    output reg [7:0]               match_len,
    output reg                     done,
    output reg                     busy
);
    localparam IDLE  = 2'd0;
    localparam SCAN  = 2'd1;
    localparam OUTPUT = 2'd2;
    localparam DONE  = 2'd3;

    reg [1:0] st;
    reg [$clog2(NUM_PRINTS):0] idx;
    reg [3:0] best_proto;
    reg [7:0] best_score;
    reg [7:0] best_len;

    // ROM interface
    wire [$clog2(NUM_PRINTS)-1:0] rom_addr = idx[$clog2(NUM_PRINTS)-1:0];
    wire [3:0] rom_proto;
    wire [7:0] rom_len;
    wire [MAX_PATTERN_BITS-1:0] rom_pat;

    fingerprint_rom #(.NUM_PRINTS(NUM_PRINTS), .MAX_PATTERN_BITS(MAX_PATTERN_BITS)) u_rom (
        .clk(clk), .rst_n(rst_n), .rd_addr(rom_addr),
        .proto_id(rom_proto), .pattern_len(rom_len), .pattern(rom_pat));

    // Hamming distance calculator
    wire [MAX_PATTERN_BITS-1:0] xor_result = frame_data ^ rom_pat;
    wire [7:0] hamming_dist;
    // Count bits in xor_result (up to MAX_PATTERN_BITS)
    // Simplified: use a parallel counter for up to 64 bits
    reg [7:0] bit_count;
    integer k;
    always @* begin
        bit_count = 8'd0;
        for (k = 0; k < MAX_PATTERN_BITS; k = k + 1)
            if (xor_result[k]) bit_count = bit_count + 1'b1;
    end
    assign hamming_dist = bit_count;

    // Score: normalized Hamming distance (0=perfect match)
    // Scale by pattern length for fair comparison
    wire [15:0] score_scaled = (hamming_dist * 8'd255) / (rom_len > 0 ? rom_len : 8'd1);
    wire [7:0] score = score_scaled[7:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= IDLE;
            match_valid <= 1'b0;
            match_proto <= 4'd0;
            match_score <= 8'd255;
            match_len <= 8'd0;
            done <= 1'b0;
            busy <= 1'b0;
            idx <= 0;
            best_proto <= 4'd0;
            best_score <= 8'd255;
            best_len <= 8'd0;
        end else begin
            match_valid <= 1'b0;
            done <= 1'b0;

            case (st)
                IDLE: begin
                    if (frame_valid) begin
                        st <= SCAN;
                        idx <= 0;
                        best_proto <= 4'd0;
                        best_score <= 8'd255;
                        best_len <= 8'd0;
                        busy <= 1'b1;
                    end
                end

                SCAN: begin
                    // Skip if proto_hint doesn't match
                    if (!hint_valid || (rom_proto == proto_hint)) begin
                        if (score < best_score) begin
                            best_score <= score;
                            best_proto <= rom_proto;
                            best_len <= rom_len;
                        end
                    end

                    if (idx == NUM_PRINTS - 1) begin
                        st <= OUTPUT;
                    end else begin
                        idx <= idx + 1'b1;
                    end
                end

                OUTPUT: begin
                    match_proto <= best_proto;
                    match_score <= best_score;
                    match_len <= best_len;
                    match_valid <= 1'b1;
                    st <= DONE;
                end

                DONE: begin
                    done <= 1'b1;
                    busy <= 1'b0;
                    st <= IDLE;
                end
            endcase
        end
    end
endmodule
