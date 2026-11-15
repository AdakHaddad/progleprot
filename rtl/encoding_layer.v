// encoding_layer: Shared encoding/decoding layer for serial protocols.
// Supports: NRZ, NRZI, Manchester, Bit-stuffing (CAN, USB)
// Can be used as pre-processor for framer or post-processor for sequencer.

module encoding_layer #(
    parameter CNT_W = 16,
    parameter MODE_NRZ      = 2'd0,
    parameter MODE_NRZI     = 2'd1,
    parameter MODE_MANCHESTER = 2'd2,
    parameter MODE_STUFFING = 2'd3
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire [1:0]              mode,
    input  wire                    bit_in,      // Raw bit from channel
    input  wire                    bit_valid,   // Bit is valid (sampled at bit rate)
    output reg                     bit_out,     // Decoded bit
    output reg                     bit_out_valid,
    // Stuffing control
    input  wire [3:0]              stuff_after, // Stuff after N consecutive same bits (0=disable)
    output reg                     stuff_error  // Stuffing violation detected
);

    // State for decoding
    reg prev_bit;
    reg [3:0] same_count;       // Count of consecutive same bits OUTPUT
    reg prev_bit_valid;
    reg waiting_for_stuff;      // True when we've hit threshold, next bit is stuff

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_out <= 1'b0;
            bit_out_valid <= 1'b0;
            prev_bit <= 1'b1;   // Idle high
            same_count <= 4'd0;
            prev_bit_valid <= 1'b0;
            stuff_error <= 1'b0;
            waiting_for_stuff <= 1'b0;
        end else begin
            bit_out_valid <= 1'b0;
            stuff_error <= 1'b0;

            if (bit_valid) begin
                case (mode)
                    MODE_NRZ: begin
                        bit_out <= bit_in;
                        bit_out_valid <= 1'b1;
                        same_count <= 4'd0;
                        waiting_for_stuff <= 1'b0;
                        prev_bit <= bit_in;
                        prev_bit_valid <= 1'b1;
                    end

                    MODE_NRZI: begin
                        if (prev_bit_valid) begin
                            bit_out <= (bit_in == prev_bit) ? 1'b1 : 1'b0;
                            bit_out_valid <= 1'b1;
                        end
                        prev_bit <= bit_in;
                        prev_bit_valid <= 1'b1;
                        same_count <= 4'd0;
                        waiting_for_stuff <= 1'b0;
                    end

                    MODE_MANCHESTER: begin
                        if (prev_bit_valid) begin
                            bit_out <= (bit_in == 1'b0 && prev_bit == 1'b1) ? 1'b0 : 1'b1;
                            bit_out_valid <= 1'b1;
                        end
                        prev_bit <= bit_in;
                        prev_bit_valid <= 1'b1;
                        same_count <= 4'd0;
                        waiting_for_stuff <= 1'b0;
                    end

                    MODE_STUFFING: begin
                        if (stuff_after == 0) begin
                            // Stuffing disabled
                            bit_out <= bit_in;
                            bit_out_valid <= 1'b1;
                            same_count <= 4'd0;
                            waiting_for_stuff <= 1'b0;
                            prev_bit <= bit_in;
                            prev_bit_valid <= 1'b1;
                        end else if (waiting_for_stuff) begin
                            // We've output N same bits, next wire bit is stuff bit (inverted)
                            // Check if stuff bit is correctly inverted
                            if (bit_in == prev_bit) begin
                                stuff_error <= 1'b1; // Stuff bit NOT inverted!
                            end
                            // Stuff bit is REMOVED from output stream
                            // Reset for next run
                            same_count <= 4'd0;
                            waiting_for_stuff <= 1'b0;
                            prev_bit <= bit_in;
                            prev_bit_valid <= 1'b1;
                            // NO bit_out_valid - stuff bit is discarded
                        end else if (prev_bit_valid && bit_in == prev_bit) begin
                            // Continuing same bit run
                            if (same_count + 1 == stuff_after) begin
                                // This bit reaches threshold - output it, next wire bit is stuff
                                bit_out <= bit_in;
                                bit_out_valid <= 1'b1;
                                same_count <= same_count + 1'b1;
                                waiting_for_stuff <= 1'b1; // Next bit is stuff
                                prev_bit <= bit_in;
                            end else begin
                                // Normal same bit
                                bit_out <= bit_in;
                                bit_out_valid <= 1'b1;
                                same_count <= same_count + 1'b1;
                                prev_bit <= bit_in;
                            end
                        end else begin
                            // Transition or first bit
                            bit_out <= bit_in;
                            bit_out_valid <= 1'b1;
                            same_count <= 4'd1;
                            waiting_for_stuff <= 1'b0;
                            prev_bit <= bit_in;
                            prev_bit_valid <= 1'b1;
                        end
                    end

                    default: begin
                        bit_out <= bit_in;
                        bit_out_valid <= 1'b1;
                        same_count <= 4'd0;
                        waiting_for_stuff <= 1'b0;
                        prev_bit <= bit_in;
                        prev_bit_valid <= 1'b1;
                    end
                endcase
            end
        end
    end
endmodule


// crc_sweep: Sweeps common CRC polynomials against frame data
module crc_sweep #(
    parameter FRAME_BITS = 64,
    parameter NUM_POLYS = 8
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    frame_valid,
    input  wire [FRAME_BITS-1:0]   frame_data,
    input  wire [7:0]              frame_len,
    output reg                     crc_valid,
    output reg [3:0]               crc_poly_id,
    output reg                     crc_match
);

    // Common CRC polynomials
    localparam POLY_CRC5_USB   = 16'h05;  // x^5 + x^2 + 1
    localparam POLY_CRC8_ATM   = 16'h07;  // x^8 + x^2 + x + 1
    localparam POLY_CRC8_MAXIM = 16'h31;  // x^8 + x^5 + x^4 + 1
    localparam POLY_CRC16_CCITT = 16'h1021; // x^16 + x^12 + x^5 + 1
    localparam POLY_CRC16_IBM  = 16'h8005; // x^16 + x^15 + x^2 + 1
    localparam POLY_CRC15_CAN  = 16'h4599; // CAN CRC-15

    reg [15:0] polys [0:NUM_POLYS-1];
    reg [4:0]  poly_bits [0:NUM_POLYS-1];

    initial begin
        polys[0] = POLY_CRC5_USB;     poly_bits[0] = 5;
        polys[1] = POLY_CRC8_ATM;     poly_bits[1] = 8;
        polys[2] = POLY_CRC8_MAXIM;   poly_bits[2] = 8;
        polys[3] = POLY_CRC16_CCITT;  poly_bits[3] = 16;
        polys[4] = POLY_CRC16_IBM;    poly_bits[4] = 16;
        polys[5] = POLY_CRC15_CAN;    poly_bits[5] = 15;
        polys[6] = 16'h0000;          poly_bits[6] = 0;  // placeholder
        polys[7] = 16'h0000;          poly_bits[7] = 0;  // placeholder
    end

    localparam S_IDLE = 2'd0, S_SWEEP = 2'd1, S_DONE = 2'd2;
    reg [1:0] st;
    reg [$clog2(NUM_POLYS):0] poly_idx;
    reg [FRAME_BITS-1:0] data_shift;
    reg [15:0] crc_reg;
    reg [7:0] bit_cnt;
    reg found_match;

    // Loop variable for CRC computation
    integer k;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE;
            crc_valid <= 1'b0;
            crc_poly_id <= 4'd0;
            crc_match <= 1'b0;
            poly_idx <= 0;
            bit_cnt <= 0;
            crc_reg <= 0;
            data_shift <= 0;
            found_match <= 1'b0;
        end else begin
            crc_valid <= 1'b0;

            case (st)
                S_IDLE: begin
                    if (frame_valid) begin
                        st <= S_SWEEP;
                        poly_idx <= 0;
                        found_match <= 1'b0;
                    end
                end

                S_SWEEP: begin
                    if (poly_idx < NUM_POLYS && poly_bits[poly_idx] > 0) begin
                        // Compute CRC for this polynomial
                        crc_reg = 0;
                        data_shift = frame_data;
                        bit_cnt = frame_len;

                        // Use fixed FRAME_BITS loop bound for synthesis compatibility
                        for (k = 0; k < FRAME_BITS; k = k + 1) begin
                            if (k < frame_len) begin
                                if ((crc_reg[poly_bits[poly_idx]-1] ^ data_shift[frame_len-1-k]) == 1'b1)
                                    crc_reg = (crc_reg << 1) ^ polys[poly_idx];
                                else
                                    crc_reg = crc_reg << 1;
                            end
                        end

                        // Check if remainder is zero (valid CRC)
                        if (crc_reg == 0) begin
                            crc_poly_id <= poly_idx;
                            crc_match <= 1'b1;
                            found_match <= 1'b1;
                        end

                        poly_idx <= poly_idx + 1'b1;
                    end else begin
                        st <= S_DONE;
                    end
                end

                S_DONE: begin
                    crc_valid <= 1'b1;
                    if (!found_match) crc_match <= 1'b0;
                    st <= S_IDLE;
                end
            endcase
        end
    end
endmodule


// manchester_decoder: Decodes Manchester-encoded bitstream (10BASE-T)
module manchester_decoder #(
    parameter OVERSAMPLE = 8  // Samples per bit (must be even)
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    signal_in,    // Manchester signal
    input  wire                    sample_en,    // Sample enable (OVERSAMPLE x bit rate)
    output reg                     bit_out,
    output reg                     bit_valid,
    output reg                     sync_found,
    output reg                     code_violation
);

    localparam S_SYNC  = 2'd0;
    localparam S_DECODE = 2'd1;

    reg [1:0] st;
    reg [$clog2(OVERSAMPLE):0] sample_cnt;
    reg [1:0] half_bit;  // 0=first half, 1=second half
    reg prev_sample;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_SYNC;
            sample_cnt <= 0;
            half_bit <= 0;
            prev_sample <= 1'b1;
            bit_out <= 1'b0;
            bit_valid <= 1'b0;
            sync_found <= 1'b0;
            code_violation <= 1'b0;
        end else begin
            bit_valid <= 1'b0;
            code_violation <= 1'b0;

            if (sample_en) begin
                case (st)
                    S_SYNC: begin
                        // Look for mid-bit transition (sync pattern)
                        if (signal_in != prev_sample) begin
                            // Transition found - could be sync
                            half_bit <= 1; // Next sample is second half
                            sample_cnt <= 1;
                            sync_found <= 1'b1;
                            st <= S_DECODE;
                        end
                        prev_sample <= signal_in;
                    end

                    S_DECODE: begin
                        sample_cnt <= sample_cnt + 1'b1;

                        if (sample_cnt == OVERSAMPLE/2 - 1) begin
                            // First half sampled
                            half_bit <= 1;
                        end else if (sample_cnt == OVERSAMPLE - 1) begin
                            // Second half sampled - decode
                            // Manchester: 0 = high->low, 1 = low->high
                            bit_out <= (prev_sample == 1'b1 && signal_in == 1'b0) ? 1'b0 : 1'b1;
                            bit_valid <= 1'b1;
                            sample_cnt <= 0;
                            half_bit <= 0;
                            
                            // Check for code violation (no transition at mid-bit)
                            if (prev_sample == signal_in) begin
                                code_violation <= 1'b1;
                            end
                        end
                        prev_sample <= signal_in;
                    end
                endcase
            end
        end
    end
endmodule

