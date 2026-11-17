// uart_framer: waits for >=4 bit-times of idle-high, then a falling edge (start bit),
// verifies the start bit at mid-bit, then reads 10 slots. Each slot is sampled three times
// (25%, 50%, 75% of the bit) and majority-voted, so a short glitch cannot flip a bit.
// bits[k-1] = voted value of slot k, k = 1..10. frame_valid pulses when bits is complete.
// Assumes idle-high UART and LSB-first. Frames must be separated by idle >= 4 bit-times
// plus the 10-slot window (back-to-back streams are not handled yet).
module uart_framer #(
    parameter CNT_W = 16
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             en,
    input  wire             sig,
    input  wire [CNT_W-1:0] bit_cycles,
    output reg              frame_valid,
    output reg  [9:0]       bits
);
    localparam S_WAIT = 2'd0, S_ARM = 2'd1, S_START = 2'd2, S_SAMPLE = 2'd3;
    reg [1:0]       st;
    reg [CNT_W+1:0] hi_cnt;
    reg [CNT_W-1:0] pc;
    reg [3:0]       slot;
    reg             sa, sb, sc;
    wire [CNT_W-1:0] half    = bit_cycles >> 1;
    wire [CNT_W-1:0] quarter = bit_cycles >> 2;
    wire [CNT_W+1:0] gap_thr = {bit_cycles, 2'b00};   // 4 bit-times
    wire maj = (sa & sb) | (sa & sc) | (sb & sc);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_WAIT; hi_cnt <= 0; pc <= 0; slot <= 0;
            sa <= 0; sb <= 0; sc <= 0;
            frame_valid <= 1'b0; bits <= 10'd0;
        end else begin
            frame_valid <= 1'b0;
            if (!en) begin
                st <= S_WAIT; hi_cnt <= 0;
            end else begin
                case (st)
                    S_WAIT: begin
                        if (sig) begin
                            if (hi_cnt >= gap_thr) st <= S_ARM;
                            else hi_cnt <= hi_cnt + 1'b1;
                        end else hi_cnt <= 0;
                    end
                    S_ARM: begin
                        if (!sig) begin st <= S_START; pc <= 0; end
                    end
                    S_START: begin
                        if (pc == half) begin
                            if (sig) begin st <= S_WAIT; hi_cnt <= 0; end   // glitch, not a start bit
                            else begin
                                st <= S_SAMPLE;
                                pc <= bit_cycles - half;   // about half a bit to the slot-1 boundary
                                slot <= 4'd0;              // slot 0 = remainder of the start bit
                            end
                        end else pc <= pc + 1'b1;
                    end
                    S_SAMPLE: begin
                        if (pc == half - quarter) sa <= sig;
                        if (pc == half)           sb <= sig;
                        if (pc == half + quarter) sc <= sig;
                        if (pc >= bit_cycles - 1'b1) begin
                            pc <= 0;
                            if (slot != 4'd0) bits[slot-1] <= maj;
                            if (slot == 4'd10) begin
                                frame_valid <= 1'b1;
                                st <= S_WAIT; hi_cnt <= 0;
                            end else slot <= slot + 1'b1;
                        end else pc <= pc + 1'b1;
                    end
                endcase
            end
        end
    end
endmodule
