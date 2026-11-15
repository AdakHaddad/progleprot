// ps2_detect: PS/2 keyboard/mouse protocol detector
// PS/2: Clocked serial, 11-bit frames (start=0, 8 data, parity=odd, stop=1)
// Host-to-device and device-to-host use same format

`timescale 1ns/1ps

module ps2_detect #(
    parameter CNT_W = 16,
    parameter IDX_W = 8,
    parameter BIN_W = 8
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    clk_pin,     // PS/2 clock line
    input  wire                    data_pin,    // PS/2 data line
    output reg                     frame_valid,
    output reg [10:0]              frame_bits,  // {stop, parity, data[7:0], start}
    output reg                     parity_error,
    output reg [7:0]               n_frames,
    output reg                     direction    // 0=device->host, 1=host->device (inferred from timing)
);

    // Edge detection on clock line (3-flop synchronizer)
    reg clk_q1, clk_q2, clk_q3;
    wire clk_negedge = clk_q2 & ~clk_q1;  // Data valid on falling clock edge
    wire clk_posedge = ~clk_q2 & clk_q1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_q1 <= 1'b1; clk_q2 <= 1'b1; clk_q3 <= 1'b1;
        end else begin
            clk_q1 <= clk_pin;
            clk_q2 <= clk_q1;
            clk_q3 <= clk_q2;
        end
    end

    // Data line sampling (2-flop synchronizer) - use data_q1 for aligned sampling
    reg data_q1, data_q2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_q1 <= 1'b1; data_q2 <= 1'b1;
        end else begin
            data_q1 <= data_pin;
            data_q2 <= data_q1;
        end
    end

    // Shift register for frame assembly
    reg [3:0] bit_cnt;
    reg [10:0] shift_reg;
    reg in_frame;
    reg [15:0] timeout_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_valid <= 1'b0;
            frame_bits <= 11'd0;
            parity_error <= 1'b0;
            n_frames <= 8'd0;
            bit_cnt <= 4'd0;
            shift_reg <= 11'd0;
            in_frame <= 1'b0;
            direction <= 1'b0;
            timeout_cnt <= 16'd0;
        end else begin
            frame_valid <= 1'b0;

            // Timeout counter - reset on any clock edge
            if (clk_negedge || clk_posedge) begin
                timeout_cnt <= 16'd0;
            end else if (in_frame) begin
                timeout_cnt <= timeout_cnt + 1'b1;
            end

            if (clk_negedge) begin
                // Sample data on falling clock edge - use data_q1 (aligned with clk_q2)
                if (!in_frame) begin
                    // Look for start bit (0)
                    if (data_q1 == 1'b0) begin
                        in_frame <= 1'b1;
                        bit_cnt <= 4'd0;
                        shift_reg <= 11'd0;
                    end
                end else begin
                    shift_reg <= {data_q1, shift_reg[10:1]};
                    bit_cnt <= bit_cnt + 1'b1;

                    // Check for frame complete: 11 bits = start(1) + data(8) + parity(1) + stop(1)
                    // bit_cnt goes 0->10 (11 bits total). At bit_cnt=10 we have received stop bit.
                    if (bit_cnt == 4'd9) begin  // Next increment will make it 10 (stop bit)
                        frame_bits <= {data_q1, shift_reg[10:1]};
                        frame_valid <= 1'b1;
                        n_frames <= n_frames + 1'b1;
                        parity_error <= ^({data_q1, shift_reg[10:1]}) == 1'b0;
                        in_frame <= 1'b0;
                    end
                end
            end

            // Timeout detection - if clock stays high/low too long, reset frame
            if (timeout_cnt > 16'd10000 && in_frame) begin
                in_frame <= 1'b0;
            end
        end
    end
endmodule


// ps2_decoder: Decodes PS/2 scan codes to key events
module ps2_decoder (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        frame_valid,
    input  wire [10:0] frame_bits,
    input  wire        parity_error,
    output reg         key_valid,
    output reg [7:0]   key_code,
    output reg         key_down,    // 1=make, 0=break
    output reg         extended
);

    // PS/2 scan code states
    localparam S_IDLE    = 2'd0;
    localparam S_EXTENDED = 2'd1;
    localparam S_RELEASE  = 2'd2;
    localparam S_REL_EXT  = 2'd3;

    reg [1:0] st;
    reg [7:0] prev_code;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE;
            key_valid <= 1'b0;
            key_code <= 8'd0;
            key_down <= 1'b1;
            extended <= 1'b0;
            prev_code <= 8'd0;
        end else begin
            key_valid <= 1'b0;

            if (frame_valid && !parity_error) begin
                // Extract 8-bit data from frame (bits 8:1)
                reg [7:0] code;
                code = frame_bits[8:1];

                case (st)
                    S_IDLE: begin
                        if (code == 8'hE0) begin
                            st <= S_EXTENDED;
                            extended <= 1'b1;
                        end else if (code == 8'hF0) begin
                            st <= S_RELEASE;
                            key_down <= 1'b0;
                        end else begin
                            key_code <= code;
                            key_down <= 1'b1;
                            extended <= 1'b0;
                            key_valid <= 1'b1;
                            prev_code <= code;
                        end
                    end

                    S_EXTENDED: begin
                        if (code == 8'hF0) begin
                            st <= S_REL_EXT;
                            key_down <= 1'b0;
                        end else begin
                            key_code <= code;
                            key_down <= 1'b1;
                            key_valid <= 1'b1;
                            prev_code <= code;
                            st <= S_IDLE;
                            extended <= 1'b0;
                        end
                    end

                    S_RELEASE: begin
                        key_code <= code;
                        key_down <= 1'b0;
                        key_valid <= 1'b1;
                        prev_code <= code;
                        st <= S_IDLE;
                        extended <= 1'b0;
                    end

                    S_REL_EXT: begin
                        key_code <= code;
                        key_down <= 1'b0;
                        key_valid <= 1'b1;
                        prev_code <= code;
                        st <= S_IDLE;
                        extended <= 1'b0;
                    end
                endcase
            end
        end
    end
endmodule

