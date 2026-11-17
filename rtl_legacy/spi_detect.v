// spi_detect: SPI clock/data role discovery and mode inference.
// Continuously monitors two pins + CS. Detects frames when CS is asserted.
module spi_detect #(
    parameter CNT_W = 16,
    parameter IDX_W = 6,
    parameter BIN_W = 8
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             pin_a,
    input  wire             pin_b,
    input  wire             cs_n,         // active-low chip select
    input  wire             hist_ev,      // histogram event (unused, kept for compatibility)
    input  wire [CNT_W-1:0] hist_interval,
    input  wire [IDX_W-1:0] hist_bucket,
    output reg              role_a_is_clk, // 1 = A=clock, B=data; 0 = B=clock, A=data
    output reg [1:0]        mode,          // {CPOL, CPHA}
    output reg              frame_valid,
    output reg [11:0]       frame_bits,
    output reg [7:0]        n_frames
);
    localparam S_IDLE    = 2'd0;
    localparam S_ROLE    = 2'd1;
    localparam S_FRAME   = 3'd2;

    reg [1:0] st;
    reg [7:0] ev_cnt;
    reg [3:0] a_edges, b_edges;

    // Synchronized inputs (2-flop)
    reg a_sync, a_prev, b_sync, b_prev, cs_sync, cs_prev;

    wire a_edge = (a_sync != a_prev);
    wire b_edge = (b_sync != b_prev);
    wire cs_fall = (cs_prev && !cs_sync);
    wire cs_rise = (!cs_prev && cs_sync);

    // Clock/data pin selection
    wire clk_pin_sync = role_a_is_clk ? a_sync : b_sync;
    wire clk_pin_prev = role_a_is_clk ? a_prev : b_prev;
    wire data_pin_sync = role_a_is_clk ? b_sync : a_sync;
    wire clk_edge = (clk_pin_sync != clk_pin_prev);

    reg [11:0] bit_cnt;
    reg [15:0] shift_reg;
    reg        first_clk_edge;
    reg        cpol_sampled;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE;
            role_a_is_clk <= 1'b1;
            mode <= 2'd0;
            frame_valid <= 1'b0;
            frame_bits <= 12'd0;
            n_frames <= 8'd0;
            ev_cnt <= 8'd0;
            a_edges <= 4'd0; b_edges <= 4'd0;
            a_sync <= 1'b1; a_prev <= 1'b1;
            b_sync <= 1'b1; b_prev <= 1'b1;
            cs_sync <= 1'b1; cs_prev <= 1'b1;
            bit_cnt <= 12'd0;
            shift_reg <= 16'd0;
            first_clk_edge <= 1'b1;
            cpol_sampled <= 1'b0;
        end else begin
            frame_valid <= 1'b0;

            a_prev <= a_sync; a_sync <= pin_a;
            b_prev <= b_sync; b_sync <= pin_b;
            cs_prev <= cs_sync; cs_sync <= cs_n;

            case (st)
                S_IDLE: begin
                    // Wait for CS fall to start role detection
                    if (cs_fall) begin
                        st <= S_ROLE;
                        a_edges <= 4'd0; b_edges <= 4'd0;
                        ev_cnt <= 8'd0;
                        first_clk_edge <= 1'b1;
                        cpol_sampled <= 1'b0;
                    end
                end

                S_ROLE: begin
                    // Count edges on both pins while CS is low
                    if (a_edge) a_edges <= a_edges + 1'b1;
                    if (b_edge) b_edges <= b_edges + 1'b1;

                    // Sample CPOL on first clock edge after CS fall
                    if (clk_edge && !cpol_sampled) begin
                        mode[1] <= clk_pin_sync;  // CPOL = clock idle level
                        cpol_sampled <= 1'b1;
                    end

                    if (cs_rise) begin
                        // CS rose - decide role and go to frame state for next frame
                        role_a_is_clk <= (a_edges >= b_edges);
                        st <= S_FRAME;
                        bit_cnt <= 12'd0;
                        shift_reg <= 16'd0;
                        first_clk_edge <= 1'b1;
                        cpol_sampled <= 1'b0;
                    end
                end

                S_FRAME: begin
                    // Wait for next CS fall
                    if (cs_fall) begin
                        bit_cnt <= 12'd0;
                        shift_reg <= 16'd0;
                        first_clk_edge <= 1'b1;
                    end else if (clk_edge) begin
                        // Sample data on clock edge
                        shift_reg <= {shift_reg[14:0], data_pin_sync};
                        bit_cnt <= bit_cnt + 1'b1;

                        // Infer CPHA from first clock edge behavior
                        if (first_clk_edge) begin
                            // If data was already stable before first clock edge, CPHA=0
                            // If data changes on first clock edge, CPHA=1
                            // Simplified: assume CPHA=0 for now
                            mode[0] <= 1'b0;
                            first_clk_edge <= 1'b0;
                        end
                    end

                    if (cs_rise) begin
                        frame_bits <= bit_cnt;
                        frame_valid <= 1'b1;
                        n_frames <= n_frames + 1'b1;
                    end
                end

                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
