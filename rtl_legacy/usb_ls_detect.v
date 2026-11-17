// usb_ls_detect: USB Low Speed (1.5 Mbps) frame detector
// Uses NRZI + bit stuffing (after 6 consecutive 1s) + CRC-5 (token) / CRC-16 (data)
// Detects: SYNC (KJKJKJKJ), PID, ADDR/ENDPT, CRC-5/CRC-16, EOP (SE0)
//
// USB LS signaling: 
//   - NRZI: 0 = transition, 1 = no transition
//   - Bit stuffing after 6 consecutive 1s
//   - SYNC = KJKJKJKJ (8 bits) = ALL ZEROS in NRZI (max transitions for clock recovery)
//   - EOP = SE0 (both D+/D- low) for 2 bit times

module usb_ls_detect #(
    parameter CNT_W = 16,
    parameter MAX_DATA_BYTES = 64
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    usb_dp,      // D+ line
    input  wire                    usb_dn,      // D- line
    output reg                     frame_valid,
    output reg [3:0]               pid,         // Packet ID
    output reg [6:0]               addr,        // Device address
    output reg [3:0]               endpt,       // Endpoint
    output reg [MAX_DATA_BYTES*8-1:0] frame_data,
    output reg [15:0]              frame_len,   // Data length in bytes
    output reg                     crc_error,
    output reg                     stuff_error,
    output reg                     pid_error,
    output reg [7:0]               n_frames,
    output reg [4:0]               st_dbg,
    output reg [7:0]               bit_idx_dbg,
    output reg [7:0]               byte_cnt_dbg,
    output reg                     decoded_bit_dbg,
    output reg                     process_bit_dbg,
    output reg [4:0]               stuff_count_dbg,
    output reg                     expect_stuff_bit_dbg
);

    // USB LS bit period at system clock (assuming ~48MHz system clock for 1.5Mbps = 32 cycles/bit)
    reg [15:0] sample_phase;
    reg [15:0] bit_period;
    reg        usb_dp_d, usb_dn_d;
    reg        in_frame;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_phase <= 16'd0;
            bit_period <= 16'd32;  // 48MHz / 1.5Mbps = 32 cycles per bit
            usb_dp_d <= 1'b1;
            usb_dn_d <= 1'b0;
            in_frame <= 1'b0;
        end else begin
            usb_dp_d <= usb_dp;
            usb_dn_d <= usb_dn;
            if (!in_frame && usb_dp_d == 1'b1 && usb_dn_d == 1'b0 && usb_dp == 1'b0 && usb_dn == 1'b1) begin
                // K-sync start: D+ goes 1->0, D- goes 0->1 (K symbol)
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

    // Differential to NRZI decode
    reg prev_diff;
    reg [3:0] stuff_count;
    reg expect_stuff_bit;
    
    localparam S_IDLE       = 5'd0;
    localparam S_SYNC       = 5'd1;
    localparam S_PID        = 5'd2;
    localparam S_ADDR_ENDP  = 5'd3;
    localparam S_CRC5       = 5'd4;
    localparam S_DATA       = 5'd5;
    localparam S_CRC16_LO   = 5'd6;
    localparam S_CRC16_HI   = 5'd7;
    localparam S_WAIT_EOP   = 5'd9;

    // Token PIDs (4 bits): OUT=0001, IN=1001, SOF=0101, SETUP=1101
    // Data PIDs: DATA0=0011, DATA1=1011, DATA2=0111, MDATA=1111
    // Handshake PIDs: ACK=0010, NAK=1010, STALL=1110, NYET=0110
    
    // CRC active states - CRC5 only on ADDR+ENDPT (11 bits), CRC16 only on DATA
    wire crc5_active = (st == S_ADDR_ENDP);
    wire crc16_active = (st == S_DATA);

    reg [4:0] st;
    reg [7:0] bit_idx;
    reg [7:0] byte_cnt;
    reg [4:0] crc5_reg;
    reg [15:0] crc16_reg;
    reg [4:0]  crc5_received;
    reg [15:0] crc16_received;
    reg [3:0]  sync_count;
    reg [3:0]  eop_count;
    reg        is_data_packet;
    reg        is_handshake_packet;
    reg [7:0]  pid_byte;

    // CRC polynomials - USB uses reflected polynomials for LSB-first processing
    localparam CRC5_POLY  = 5'h14;    // Reflected 0x05 = 0x14 (for right-shift)
    localparam CRC16_POLY = 16'hA001; // Reflected 0x8005 = 0xA001 (for right-shift)

    // Local variables
    reg decoded_bit;
    reg process_bit;

    // Debug: trace K-sync detection in Block 1 - only on detection
    always @(posedge clk) begin
        if (!in_frame && usb_dp_d == 1'b1 && usb_dn_d == 1'b0 && usb_dp == 1'b0 && usb_dn == 1'b1) begin
            $display("  [DBG BLK1 DETECT] t=%0t K-sync! in_frame=%b usb_dp_d=%b usb_dn_d=%b usb_dp=%b usb_dn=%b", $time, in_frame, usb_dp_d, usb_dn_d, usb_dp, usb_dn);
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE;
            frame_valid <= 1'b0;
            pid <= 4'd0;
            addr <= 7'd0;
            endpt <= 4'd0;
            frame_data <= 0;
            frame_len <= 16'd0;
            crc_error <= 1'b0;
            stuff_error <= 1'b0;
            pid_error <= 1'b0;
            n_frames <= 8'd0;
            bit_idx <= 8'd0;
            byte_cnt <= 8'd0;
            crc5_reg <= 5'd0;
            crc16_reg <= 16'd0;
            crc5_received <= 5'd0;
            crc16_received <= 16'd0;
            prev_diff <= 1'b1;  // Idle J state (D+=1, D-=0)
            stuff_count <= 4'd0;
            expect_stuff_bit <= 1'b0;
            sync_count <= 4'd0;
            eop_count <= 4'd0;
            is_data_packet <= 1'b0;
            is_handshake_packet <= 1'b0;
            pid_byte <= 8'd0;
            st_dbg <= 5'd0;
            bit_idx_dbg <= 8'd0;
            byte_cnt_dbg <= 8'd0;
            decoded_bit_dbg <= 1'b0;
            process_bit_dbg <= 1'b0;
            stuff_count_dbg <= 4'd0;
            expect_stuff_bit_dbg <= 1'b0;
            decoded_bit <= 1'b0;
            process_bit <= 1'b0;
        end else begin
            // Clear errors and frame_valid every cycle (frame_valid is a pulse)
            crc_error <= 1'b0;
            stuff_error <= 1'b0;
            pid_error <= 1'b0;
            frame_valid <= 1'b0;
            st_dbg <= st;
            bit_idx_dbg <= bit_idx;
            byte_cnt_dbg <= byte_cnt;
            stuff_count_dbg <= stuff_count;
            expect_stuff_bit_dbg <= expect_stuff_bit;

            if (sample_clk) begin
                // Differential signal: J = D+ high, D- low; K = D+ low, D- high
                // SE0 = both low (EOP), SE1 = both high (invalid)
                reg diff;
                diff = usb_dp;  // J=1, K=0
                
                // USB bit stuffing: after 6 consecutive 1s, a 0 is inserted
                // We track this on the NRZI DECODED bits
                
                if (expect_stuff_bit) begin
                    // This bit should be a stuff bit (must be 0/dominant in NRZI)
                    if (decoded_bit == 1'b1) begin
                        stuff_error <= 1'b1;
                    end
                    // Discard stuff bit
                    process_bit = 1'b0;
                    expect_stuff_bit <= 1'b0;
                    stuff_count <= 4'd0;
                end else begin
                    // NRZI decode: 0 = transition, 1 = no transition
                    decoded_bit = (diff == prev_diff) ? 1'b1 : 1'b0;
                    process_bit = 1'b1;
                    
                    if (decoded_bit == 1'b1) begin
                        stuff_count <= stuff_count + 1'b1;
                        if (stuff_count + 1'b1 == 4'd6) begin
                            expect_stuff_bit <= 1'b1;
                        end
                    end else begin
                        stuff_count <= 4'd1;
                    end
                end
                prev_diff <= diff;

                // CRC5 calculation (on NRZI decoded bits) - USB uses initial value 0x1F
                // CRC5 is only on ADDR + ENDPT (11 bits), NOT on SYNC or PID
                // Using RIGHT-SHIFT with reflected polynomial (matching testbench)
                if (process_bit && crc5_active) begin
                    if ((crc5_reg[0] ^ decoded_bit) == 1'b1)
                        crc5_reg <= (crc5_reg >> 1) ^ CRC5_POLY;
                    else
                        crc5_reg <= crc5_reg >> 1;
                end

                // CRC16 calculation - USB uses initial value 0xFFFF
                // Using RIGHT-SHIFT with reflected polynomial
                if (process_bit && crc16_active) begin
                    if ((crc16_reg[0] ^ decoded_bit) == 1'b1)
                        crc16_reg <= (crc16_reg >> 1) ^ CRC16_POLY;
                    else
                        crc16_reg <= crc16_reg >> 1;
                end

                if (process_bit) begin
                    decoded_bit_dbg <= decoded_bit;
                    process_bit_dbg <= 1'b1;
                    case (st)
                        S_IDLE: begin
                            // Wait for K-sync (K = diff=0, transition from J=1)
                            if (diff == 1'b0 && prev_diff == 1'b1) begin
                                // K detected, start sync - this is the first 0 bit of SYNC
                                st <= S_SYNC;
                                sync_count <= 4'd1;  // We've seen 1 bit of sync (the first 0)
                                bit_idx <= 8'd0;
                                byte_cnt <= 8'd0;
                                crc5_reg <= 5'h1F;  // USB CRC5 initial value
                                crc16_reg <= 16'hFFFF; // USB CRC16 initial value
                                stuff_count <= 4'd1;  // First bit is 0
                                expect_stuff_bit <= 1'b0;
                                eop_count <= 4'd0;
                            end
                        end

                        S_SYNC: begin
                            // USB SYNC = KJKJKJKJ = 8 transitions = ALL ZEROS in NRZI
                            // We already got the first 0 (K transition) when entering this state
                            // Expect 7 more 0s (total 8 zeros)
                            if (sync_count < 8) begin
                                if (decoded_bit != 1'b0) begin
                                    // Invalid sync - not a transition
                                    st <= S_IDLE; in_frame <= 1'b0;
                                end else begin
                                    sync_count <= sync_count + 1'b1;
                                    if (sync_count == 7) begin
                                        // Sync complete (8 bits = 8 zeros received), next is PID
                                        st <= S_PID;
                                        bit_idx <= 8'd0;  // LSB first
                                        pid_byte <= 8'd0;
                                    end
                                end
                            end
                        end

                        S_PID: begin
                            pid_byte[bit_idx] <= decoded_bit;
                            if (bit_idx == 7) begin
                                // Check PID format (lower 4 bits are complement of upper 4)
                                if ((pid_byte[3:0] == ~pid_byte[7:4]) == 1'b0) begin
                                    pid_error <= 1'b1;
                                end
                                pid <= pid_byte[3:0];
                                // Determine packet type from PID - use blocking assignment for immediate use
                                case (pid_byte[3:0])
                                    4'h1: begin is_data_packet = 1'b0; is_handshake_packet = 1'b0; end // OUT
                                    4'h9: begin is_data_packet = 1'b0; is_handshake_packet = 1'b0; end // IN
                                    4'h5: begin is_data_packet = 1'b0; is_handshake_packet = 1'b0; end // SOF
                                    4'hD: begin is_data_packet = 1'b0; is_handshake_packet = 1'b0; end // SETUP
                                    4'h3: begin is_data_packet = 1'b1; is_handshake_packet = 1'b0; end // DATA0
                                    4'hB: begin is_data_packet = 1'b1; is_handshake_packet = 1'b0; end // DATA1
                                    4'h7: begin is_data_packet = 1'b1; is_handshake_packet = 1'b0; end // DATA2
                                    4'hF: begin is_data_packet = 1'b1; is_handshake_packet = 1'b0; end // MDATA
                                    4'h2: begin is_data_packet = 1'b0; is_handshake_packet = 1'b1; end // ACK
                                    4'hA: begin is_data_packet = 1'b0; is_handshake_packet = 1'b1; end // NAK
                                    4'hE: begin is_data_packet = 1'b0; is_handshake_packet = 1'b1; end // STALL
                                    4'h6: begin is_data_packet = 1'b0; is_handshake_packet = 1'b1; end // NYET
                                    default: begin is_data_packet = 1'b0; is_handshake_packet = 1'b0; end
                                endcase
                                if (is_data_packet) begin
                                    st <= S_DATA;
                                    bit_idx <= 8'd0;
                                    byte_cnt <= 8'd0;
                                end else if (is_handshake_packet) begin
                                    // Handshake packets have no data, go straight to wait for EOP
                                    eop_count <= 4'd0;
                                    st <= S_WAIT_EOP;
                                end else begin
                                    st <= S_ADDR_ENDP;
                                    bit_idx <= 8'd0; // LSB first
                                    crc5_reg <= 5'h1F;  // Reset CRC5 for ADDR+ENDPT
                                    eop_count <= 4'd0;
                                end
                            end else bit_idx <= bit_idx + 1'b1;
                        end

                        S_ADDR_ENDP: begin
                            // Check EOP first (SE0 for 2 bit times)
                            if (usb_dp == 1'b0 && usb_dn == 1'b0) begin
                                eop_count <= eop_count + 1'b1;
                                if (eop_count >= 1) begin
                                    crc_error <= (crc5_reg != crc5_received);
                                    if (!crc_error && !stuff_error && !pid_error) begin
                                        frame_valid <= 1'b1; frame_len <= byte_cnt; n_frames <= n_frames + 1'b1;
                                    end
                                    st <= S_WAIT_EOP; eop_count <= 4'd0;
                                end
                            end else begin
                                eop_count <= 4'd0;
                                // 7 addr bits + 4 endpt bits = 11 bits total, LSB first
                                if (bit_idx < 7) addr[bit_idx] <= decoded_bit;
                                else endpt[bit_idx - 7] <= decoded_bit;
                                if (bit_idx == 10) begin
                                    st <= S_CRC5;
                                    bit_idx <= 8'd0;  // RESET bit_idx for CRC5
                                end else bit_idx <= bit_idx + 1'b1;
                            end
                        end

                        S_CRC5: begin
                            // Check EOP first
                            if (usb_dp == 1'b0 && usb_dn == 1'b0) begin
                                eop_count <= eop_count + 1'b1;
                                if (eop_count >= 1) begin
                                    crc_error <= (crc5_reg != crc5_received);
                                    if (!crc_error && !stuff_error && !pid_error) begin
                                        frame_valid <= 1'b1; frame_len <= byte_cnt; n_frames <= n_frames + 1'b1;
                                    end
                                    st <= S_WAIT_EOP; eop_count <= 4'd0;
                                end
                            end else begin
                                eop_count <= 4'd0;
                                crc5_received[bit_idx] <= decoded_bit;
                                if (bit_idx == 4) begin
                                    // After CRC5, wait for EOP (handled above)
                                    bit_idx <= 8'd0;
                                end else bit_idx <= bit_idx + 1'b1;
                            end
                        end

                        S_DATA: begin
                            // Check EOP first - end of data payload
                            if (usb_dp == 1'b0 && usb_dn == 1'b0) begin
                                eop_count <= eop_count + 1'b1;
                                if (eop_count >= 1) begin
                                    // Data payload ended, now read CRC16 (16 bits)
                                    st <= S_CRC16_LO;
                                    bit_idx <= 8'd0;
                                    eop_count <= 4'd0;
                                end
                            end else begin
                                eop_count <= 4'd0;
                                // Store data byte
                                if (byte_cnt < MAX_DATA_BYTES) begin
                                    frame_data[byte_cnt*8 + bit_idx] <= decoded_bit;
                                end
                                if (bit_idx == 7) begin
                                    if (byte_cnt == MAX_DATA_BYTES - 1) begin
                                        // Buffer full, go to CRC16
                                        st <= S_CRC16_LO;
                                        bit_idx <= 8'd0;
                                    end else begin
                                        byte_cnt <= byte_cnt + 1'b1;
                                        bit_idx <= 8'd0;
                                    end
                                end else bit_idx <= bit_idx + 1'b1;
                            end
                        end

                        S_CRC16_LO: begin
                            // Check EOP first (SE0 during CRC16 reception)
                            if (usb_dp == 1'b0 && usb_dn == 1'b0) begin
                                eop_count <= eop_count + 1'b1;
                                if (eop_count >= 1) begin
                                    // Premature EOP during CRC16 - error
                                    crc_error <= 1'b1;
                                    st <= S_WAIT_EOP; eop_count <= 4'd0;
                                end
                            end else begin
                                eop_count <= 4'd0;
                                // Read CRC16 low byte (bits 7:0)
                                crc16_received[bit_idx] <= decoded_bit;
                                if (bit_idx == 7) begin
                                    st <= S_CRC16_HI;
                                    bit_idx <= 8'd0;
                                end else bit_idx <= bit_idx + 1'b1;
                            end
                        end

                        S_CRC16_HI: begin
                            // Check EOP first (SE0 during CRC16 reception)
                            if (usb_dp == 1'b0 && usb_dn == 1'b0) begin
                                eop_count <= eop_count + 1'b1;
                                if (eop_count >= 1) begin
                                    // Validate CRC16
                                    crc_error <= (crc16_reg != crc16_received);
                                    if (!crc_error && !stuff_error && !pid_error) begin
                                        frame_valid <= 1'b1; frame_len <= byte_cnt; n_frames <= n_frames + 1'b1;
                                    end
                                    st <= S_WAIT_EOP; eop_count <= 4'd0;
                                end
                            end else begin
                                eop_count <= 4'd0;
                                // Read CRC16 high byte (bits 15:8)
                                crc16_received[bit_idx + 8] <= decoded_bit;
                                if (bit_idx == 7) begin
                                    // After CRC16, wait for EOP
                                    eop_count <= 4'd0;
                                    st <= S_WAIT_EOP;
                                    bit_idx <= 8'd0;
                                end else bit_idx <= bit_idx + 1'b1;
                            end
                        end

                        S_WAIT_EOP: begin
                            // Wait for EOP (SE0 for 2 bit times)
                            if (usb_dp == 1'b0 && usb_dn == 1'b0) begin
                                eop_count <= eop_count + 1'b1;
                                if (eop_count >= 1) begin
                                    // Validate CRCs if not already validated
                                    if (!is_handshake_packet && !is_data_packet) begin
                                        // Token packet: check CRC5
                                        crc_error <= (crc5_reg != crc5_received);
                                    end
                                    
                                    if (!crc_error && !stuff_error && !pid_error) begin
                                        frame_valid <= 1'b1;  // Pulse frame_valid for one cycle
                                        frame_len <= byte_cnt;
                                        n_frames <= n_frames + 1'b1;
                                    end
                                    
                                    // Wait for lines to return to J state (idle)
                                    eop_count <= 4'd0;
                                    st <= S_IDLE;
                                    in_frame <= 1'b0;
                                    crc5_reg <= 5'h1F;
                                    crc16_reg <= 16'hFFFF;
                                    prev_diff <= 1'b1;
                                    stuff_count <= 4'd0;
                                    expect_stuff_bit <= 1'b0;
                                    sync_count <= 4'd0;
                                    eop_count <= 4'd0;
                                end
                            end else begin
                                eop_count <= 4'd0;
                            end
                        end
                    endcase
                end else begin
                    process_bit_dbg <= 1'b0;
                end
            end else begin
                process_bit_dbg <= 1'b0;
            end
        end
    end
endmodule
