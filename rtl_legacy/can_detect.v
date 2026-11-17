// can_detect: CAN 2.0A/B frame detector
// Uses NRZ + bit stuffing (after 5 same bits) + CRC-15
// Detects: SOF, 11/29-bit ID, RTR, DLC, Data, CRC, ACK, EOF

module can_detect #(
    parameter CNT_W = 16,
    parameter MAX_DATA_BYTES = 8
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    can_rx,
    output reg                     frame_valid,
    output reg [28:0]              frame_id,
    output reg                     extended_id,
    output reg                     rtr,
    output reg [3:0]               dlc,
    output reg [MAX_DATA_BYTES*8-1:0] frame_data,
    output reg                     crc_error,
    output reg                     stuff_error,
    output reg                     ack_error,
    output reg [7:0]               n_frames,
    output reg [3:0]               state_dbg,
    // Debug
    output reg [4:0]               st_dbg,
    output reg [4:0]               bit_idx_dbg,
    output reg [7:0]               byte_cnt_dbg,
    output reg                     decoded_bit_dbg,
    output reg                     process_bit_dbg,
    output reg [4:0]               st_prev_dbg,
    output reg [4:0]               bit_idx_next_dbg,
    output reg [3:0]               stuff_count_dbg,
    output reg                     bit_stuff_active_dbg,
    output reg                     expect_stuff_bit_dbg,
    output reg                     sample_clk_dbg
);

    reg [15:0] sample_phase;
    reg [15:0] bit_period;
    reg        can_rx_d;
    reg        in_frame;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_phase <= 16'd0;
            bit_period <= 16'd100;
            can_rx_d <= 1'b1;
            in_frame <= 1'b0;
        end else begin
            can_rx_d <= can_rx;
            if (!in_frame && can_rx_d == 1'b1 && can_rx == 1'b0) begin
                in_frame <= 1'b1;
                sample_phase <= 16'd0;
            end else if (in_frame) begin
                if (sample_phase >= bit_period - 1) sample_phase <= 16'd0;
                else sample_phase <= sample_phase + 1'b1;
            end else begin
                sample_phase <= 16'd0;
            end
        end
    end
    
    // Sample at 75% of bit period
    wire sample_clk = in_frame && (sample_phase == (bit_period * 3 / 4));

    reg prev_bit;
    reg [3:0] stuff_count;
    reg expect_stuff_bit;
    
    localparam S_IDLE        = 5'd0;
    localparam S_ID_STD      = 5'd1;
    localparam S_RTR         = 5'd2;
    localparam S_IDE         = 5'd3;
    localparam S_ID_EXT      = 5'd4;
    localparam S_R0          = 5'd5;
    localparam S_DLC         = 5'd6;
    localparam S_DLC_WAIT    = 5'd7;
    localparam S_DATA        = 5'd8;
    localparam S_CRC         = 5'd9;
    localparam S_CRC_DELIM   = 5'd10;
    localparam S_ACK_SLOT    = 5'd11;
    localparam S_ACK_DELIM   = 5'd12;
    localparam S_EOF         = 5'd13;
    localparam S_IFS         = 5'd14;

    // CRC is calculated from SOF through end of DATA field
    wire crc_active = (st == S_IDLE || (st >= S_ID_STD && st <= S_DATA));

    reg [4:0] st;
    reg [4:0] bit_idx;
    reg [7:0] byte_cnt;
    reg [15:0] crc_reg;
    reg [14:0] crc_received;
    reg [3:0]  eof_count;
    reg [3:0]  dlc_reg;

    localparam CRC15_POLY = 16'h4599;

    // Local variables for sample_clk block
    reg decoded_bit;
    reg process_bit;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE;
            frame_valid <= 1'b0;
            frame_id <= 29'd0;
            extended_id <= 1'b0;
            rtr <= 1'b0;
            dlc <= 4'd0;
            frame_data <= 0;
            crc_error <= 1'b0;
            stuff_error <= 1'b0;
            ack_error <= 1'b0;
            n_frames <= 8'd0;
            bit_idx <= 5'd0;
            byte_cnt <= 8'd0;
            crc_reg <= 16'd0;
            crc_received <= 15'd0;
            prev_bit <= 1'b1;
            stuff_count <= 4'd0;
            expect_stuff_bit <= 1'b0;
            state_dbg <= 4'd0;
            eof_count <= 4'd0;
            in_frame <= 1'b0;
            dlc_reg <= 4'd0;
            st_dbg <= 5'd0;
            st_prev_dbg <= 5'd0;
            bit_idx_dbg <= 5'd0;
            byte_cnt_dbg <= 8'd0;
            decoded_bit_dbg <= 1'b0;
            process_bit_dbg <= 1'b0;
            bit_idx_next_dbg <= 5'd0;
            stuff_count_dbg <= 4'd0;
            bit_stuff_active_dbg <= 1'b0;
            expect_stuff_bit_dbg <= 1'b0;
            sample_clk_dbg <= 1'b0;
            decoded_bit <= 1'b0;
            process_bit <= 1'b0;
        end else begin
            // Clear errors every cycle (they're pulse outputs)
            crc_error <= 1'b0;
            stuff_error <= 1'b0;
            ack_error <= 1'b0;
            state_dbg <= st;
            st_dbg <= st;
            st_prev_dbg <= st_dbg;

            if (sample_clk) begin
                sample_clk_dbg <= 1'b1;
                
                // Standard CAN bit destuffing:
                // - Count consecutive bits of same polarity (stuff_count)
                // - When count REACHES 5 (after processing 5th bit), set expect_stuff_bit
                // - On NEXT cycle, if expect_stuff_bit, the incoming bit is stuff bit (must be opposite)
                // - Stuff bit is discarded, count resets to 0, expect_stuff_bit clears
                
                if (expect_stuff_bit) begin
                    // This bit should be a stuff bit (opposite polarity)
                    if (can_rx == prev_bit) begin
                        // Stuff error: stuff bit has same polarity as the 5 data bits
                        stuff_error <= 1'b1;
                    end
                    // Discard stuff bit
                    decoded_bit = prev_bit;  // Not used since process_bit=0
                    process_bit = 1'b0;
                    expect_stuff_bit <= 1'b0;
                    stuff_count <= 4'd0;
                    bit_stuff_active_dbg <= 1'b1;
                end else begin
                    // Normal data bit
                    decoded_bit = can_rx;
                    process_bit = 1'b1;
                    if (can_rx == prev_bit) begin
                        stuff_count <= stuff_count + 1'b1;
                        // If we just reached 5 consecutive, next bit will be stuff bit
                        if (stuff_count + 1'b1 == 4'd5) begin
                            expect_stuff_bit <= 1'b1;
                        end
                    end else begin
                        stuff_count <= 4'd1;
                    end
                    bit_stuff_active_dbg <= 1'b0;
                end
                prev_bit <= can_rx;

                // CRC calculation (only on processed bits, not stuff bits, only in CRC-active states)
                if (process_bit && crc_active) begin
                    if ((crc_reg[14] ^ decoded_bit) == 1'b1) begin
                        crc_reg <= ((crc_reg << 1) | 1'b1) ^ CRC15_POLY;
                    end else begin
                        crc_reg <= (crc_reg << 1) | 1'b0;
                    end
                end

                if (process_bit) begin
                    bit_idx_dbg <= bit_idx;
                    byte_cnt_dbg <= byte_cnt;
                    decoded_bit_dbg <= decoded_bit;
                    process_bit_dbg <= 1'b1;
                    stuff_count_dbg <= stuff_count;
                    expect_stuff_bit_dbg <= expect_stuff_bit;
                    case (st)
                        S_IDLE: begin
                            if (decoded_bit == 1'b0) begin // SOF
                                frame_valid <= 1'b0;
                                st <= S_ID_STD;
                                bit_idx <= 5'd10;
                                frame_id <= 29'd0;
                                frame_data <= 0;
                                byte_cnt <= 8'd0;
                                stuff_count <= 4'd0;
                                expect_stuff_bit <= 1'b0;
                                prev_bit <= 1'b0;
                                eof_count <= 4'd0;
                                dlc_reg <= 4'd0;
                            end
                        end

                        S_ID_STD: begin
                            frame_id[bit_idx] <= decoded_bit;
                            if (bit_idx == 0) st <= S_RTR;
                            else bit_idx <= bit_idx - 1'b1;
                        end

                        S_RTR: begin
                            rtr <= decoded_bit;
                            st <= S_IDE;
                        end

                        S_IDE: begin
                            extended_id <= decoded_bit;
                            if (decoded_bit) begin  // Extended frame
                                st <= S_ID_EXT;
                                bit_idx <= 5'd17;
                            end else begin  // Standard frame
                                st <= S_R0;
                            end
                        end

                        S_ID_EXT: begin
                            frame_id[bit_idx+11] <= decoded_bit;
                            if (bit_idx == 0) st <= S_RTR;
                            else bit_idx <= bit_idx - 1'b1;
                        end

                        S_R0: begin
                            // r0 bit (reserved, must be dominant for standard)
                            // Bit stuffing is continuous across fields (SOF to CRC delimiter)
                            // Do NOT reset stuff_count here
                            st <= S_DLC;
                            bit_idx <= 5'd3;
                        end

                        S_DLC: begin
                            dlc_reg[bit_idx] <= decoded_bit;
                            if (bit_idx == 0) begin
                                dlc <= dlc_reg;
                                // Bit stuffing is continuous across fields (SOF to CRC delimiter)
                                // Do NOT reset stuff_count here
                                if (dlc_reg > 0) begin
                                    st <= S_DATA;
                                    byte_cnt <= 8'd0;
                                    bit_idx <= 5'd7;
                                end else begin
                                    st <= S_CRC;
                                    bit_idx <= 5'd14;
                                end
                            end else begin
                                bit_idx <= bit_idx - 1'b1;
                            end
                        end

                        S_DATA: begin
                            bit_idx_next_dbg <= (bit_idx == 0) ? (byte_cnt == dlc - 1 ? 5'd14 : 5'd7) : bit_idx - 1'b1;
                            frame_data[(dlc - 1 - byte_cnt)*8 + bit_idx] <= decoded_bit;
                            if (bit_idx == 0) begin
                                if (byte_cnt == dlc - 1) begin
                                    st <= S_CRC;
                                    bit_idx <= 5'd14;
                                end else begin
                                    byte_cnt <= byte_cnt + 1'b1;
                                    bit_idx <= 5'd7;
                                end
                            end else bit_idx <= bit_idx - 1'b1;
                        end

                        S_CRC: begin
                            crc_received[bit_idx] <= decoded_bit;
                            if (bit_idx == 0) st <= S_CRC_DELIM;
                            else bit_idx <= bit_idx - 1'b1;
                        end

                        S_CRC_DELIM: begin
                            if (decoded_bit != 1'b1) crc_error <= 1'b1;
                            st <= S_ACK_SLOT;
                        end

                        S_ACK_SLOT: begin
                            ack_error <= (decoded_bit == 1'b1);
                            st <= S_ACK_DELIM;
                        end

                        S_ACK_DELIM: begin
                            if (decoded_bit != 1'b1) ack_error <= 1'b1;
                            st <= S_EOF;
                            eof_count <= 4'd6;
                        end

                        S_EOF: begin
                            if (decoded_bit != 1'b1) eof_count <= 4'd6;
                            else if (eof_count == 0) st <= S_IFS;
                            else eof_count <= eof_count - 1'b1;
                        end

                        S_IFS: begin
                            crc_error <= (crc_reg[14:0] != crc_received);
                            if (crc_reg[14:0] == crc_received && !stuff_error && !ack_error) begin
                                frame_valid <= 1'b1;
                                n_frames <= n_frames + 1'b1;
                            end
                            st <= S_IDLE;
                            in_frame <= 1'b0;
                            crc_reg <= 16'd0;
                        end
                    endcase
                end else begin
                    process_bit_dbg <= 1'b0;
                end
            end else begin
                sample_clk_dbg <= 1'b0;
                process_bit_dbg <= 1'b0;
            end
        end
    end
endmodule
