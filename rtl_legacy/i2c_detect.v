// i2c_detect: I²C start/stop detection, address + ACK framing.
// Watches SDA and SCL. Detects START (SDA falls while SCL high) and STOP (SDA rises while SCL high).
// Extracts 7-bit address + R/W bit + ACK per frame.
module i2c_detect #(
    parameter CNT_W = 16
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             sda,
    input  wire             scl,
    output reg              frame_valid,
    output reg [7:0]        addr,       // 7-bit address + R/W in bit 0
    output reg              ack,        // 0 = ACK, 1 = NACK
    output reg              is_read,    // 1 = read (master reads), 0 = write
    output reg [7:0]        n_frames
);
    localparam S_IDLE   = 2'd0;
    localparam S_ADDR   = 2'd1;
    localparam S_ACK    = 2'd2;
    localparam S_DATA   = 3'd3;

    reg [1:0]   st;
    reg [3:0]   bit_cnt;
    reg [7:0]   shift_reg;
    // 3-flop synchronizer for reliable edge detection
    reg         sda_q1, sda_q2, sda_q3;
    reg         scl_q1, scl_q2, scl_q3;

    wire sda_curr = sda_q2;
    wire sda_prev = sda_q3;
    wire scl_curr = scl_q2;
    wire scl_prev = scl_q3;

    // START: SDA falls while SCL high (sda_prev=1, sda_curr=0, scl_curr=1)
    // STOP:  SDA rises while SCL high (sda_prev=0, sda_curr=1, scl_curr=1)
    wire start_cond = sda_prev && !sda_curr && scl_curr;
    wire stop_cond  = !sda_prev && sda_curr && scl_curr;

    // SCL edges
    wire scl_rise = !scl_prev && scl_curr;
    wire scl_fall = scl_prev && !scl_curr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE;
            frame_valid <= 1'b0;
            addr <= 8'd0;
            ack <= 1'b1;
            is_read <= 1'b0;
            n_frames <= 8'd0;
            bit_cnt <= 4'd0;
            shift_reg <= 8'd0;
            sda_q1 <= 1'b1; sda_q2 <= 1'b1; sda_q3 <= 1'b1;
            scl_q1 <= 1'b1; scl_q2 <= 1'b1; scl_q3 <= 1'b1;
        end else begin
            frame_valid <= 1'b0;

            // 3-flop synchronizers
            sda_q1 <= sda; sda_q2 <= sda_q1; sda_q3 <= sda_q2;
            scl_q1 <= scl; scl_q2 <= scl_q1; scl_q3 <= scl_q2;

            case (st)
                S_IDLE: begin
                    if (start_cond) begin
                        st <= S_ADDR;
                        bit_cnt <= 4'd0;
                        shift_reg <= 8'd0;
                    end
                end

                S_ADDR: begin
                    if (scl_rise) begin
                        shift_reg <= {shift_reg[6:0], sda_curr};
                        bit_cnt <= bit_cnt + 1'b1;
                        if (bit_cnt == 4'd7) begin
                            addr <= {shift_reg[6:0], sda_curr};
                            is_read <= sda_curr;
                            st <= S_ACK;
                        end
                    end
                    if (stop_cond) st <= S_IDLE;
                    if (start_cond) begin
                        st <= S_ADDR;
                        bit_cnt <= 4'd0;
                        shift_reg <= 8'd0;
                    end
                end

                S_ACK: begin
                    if (scl_rise) begin
                        ack <= sda_curr;
                        if (sda_curr == 1'b0) begin
                            st <= S_DATA;
                        end else begin
                            st <= S_IDLE;
                        end
                    end
                    if (stop_cond) st <= S_IDLE;
                    if (start_cond) begin
                        st <= S_ADDR;
                        bit_cnt <= 4'd0;
                        shift_reg <= 8'd0;
                    end
                end

                S_DATA: begin
                    if (stop_cond) begin
                        frame_valid <= 1'b1;
                        n_frames <= n_frames + 1'b1;
                        st <= S_IDLE;
                    end
                    if (start_cond) begin
                        st <= S_ADDR;
                        bit_cnt <= 4'd0;
                        shift_reg <= 8'd0;
                    end
                end

                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
