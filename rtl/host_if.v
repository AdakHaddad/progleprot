/*
 * host_if: SPI slave interface for loading program RAM.
 * Supports configurable DATA_W (16 or 32 bits).
 * For 16-bit mode, each 32-bit SPI data payload is split into two 16-bit words.
 */
module host_if #(
    parameter ADDR_W = 8,
    parameter DATA_W = 16
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    spi_sck,
    input  wire                    spi_mosi,
    output wire                    spi_miso,
    input  wire                    spi_cs_n,
    output reg                     ram_wr_en,
    output reg  [ADDR_W-1:0]       ram_wr_addr,
    output reg  [DATA_W-1:0]       ram_wr_data,
    output reg                     seq_start,
    output reg  [ADDR_W-1:0]       seq_prog_len,
    output reg [1:0]               host_state
);

    localparam CMD_WRITE    = 8'h01;
    localparam CMD_READBACK = 8'h02;
    localparam CMD_RUN      = 8'h03;

    localparam S_IDLE    = 2'd0;
    localparam S_SHIFT   = 2'd1;
    localparam S_EXECUTE = 2'd2;

    reg [1:0] st;
    reg [6:0] bit_cnt;
    reg [63:0] shift_reg;
    reg [7:0] cmd;
    reg [15:0] addr;
    reg [31:0] data;
    reg sck_prev;
    reg cs_n_prev;
    reg [1:0] write_phase; // For 16-bit mode: 0=write low 16 bits, 1=write high 16 bits

    wire sck_rise = !sck_prev && spi_sck;
    wire sck_fall = sck_prev && !spi_sck;
    wire cs_fall = cs_n_prev && !spi_cs_n;
    wire cs_rise = !cs_n_prev && spi_cs_n;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE;
            bit_cnt <= 7'd0;
            shift_reg <= 64'd0;
            cmd <= 8'd0;
            addr <= 16'd0;
            data <= 32'd0;
            ram_wr_en <= 1'b0;
            ram_wr_addr <= {ADDR_W{1'b0}};
            ram_wr_data <= {DATA_W{1'b0}};
            seq_start <= 1'b0;
            seq_prog_len <= {ADDR_W{1'b0}};
            host_state <= 2'd0;
            sck_prev <= 1'b1;
            cs_n_prev <= 1'b1;
            write_phase <= 2'd0;
        end else begin
            sck_prev <= spi_sck;
            cs_n_prev <= spi_cs_n;
            ram_wr_en <= 1'b0;
            
            // seq_start pulse: assert for 1 cycle when RUN command completes on CS rise
            if (st == S_EXECUTE && cmd == CMD_RUN && cs_rise) begin
                seq_start <= 1'b1;
            end else begin
                seq_start <= 1'b0;
            end

            case (st)
                S_IDLE: begin
                    if (cs_fall) begin
                        $display("t=%0t [HOST_IF] CS_FALL -> S_SHIFT", $time);
                        bit_cnt <= 7'd0;
                        shift_reg <= 64'd0;
                        st <= S_SHIFT;
                    end
                end

                S_SHIFT: begin
                    if (sck_fall) begin
                        // Shift LEFT: MSB-first, new bit goes to LSB
                        shift_reg = {shift_reg[62:0], spi_mosi};
                        bit_cnt = bit_cnt + 1'b1;
                        if (bit_cnt <= 8) begin
                            $display("t=%0t [HOST_IF] SHIFT bit_cnt=%d mosi=%b shift_reg=%h", $time, bit_cnt, spi_mosi, shift_reg);
                        end
                        if (bit_cnt == 7'd64) begin
                            // All 64 bits received
                            cmd   = shift_reg[15:8];
                            addr  = shift_reg[31:16];
                            data  = shift_reg[63:32];
                            $display("t=%0t [HOST_IF] CMD complete: shift_reg=%h cmd=%h addr=%h data=%h", $time, shift_reg, shift_reg[15:8], shift_reg[31:16], shift_reg[63:32]);
                            write_phase <= 2'd0;
                            st <= S_EXECUTE;
                        end
                    end
                    if (cs_rise) begin
                        st <= S_IDLE;
                    end
                end

                S_EXECUTE: begin
                    $display("t=%0t [HOST_IF] S_EXECUTE: cmd=%h addr=%h data=%h write_phase=%d cs_rise=%b", $time, cmd, addr, data, write_phase, cs_rise);
                    case (cmd)
                        CMD_WRITE: begin
                            if (DATA_W == 16) begin
                                // 16-bit mode: split 32-bit data into two 16-bit writes
                                if (write_phase == 2'd0) begin
                                    ram_wr_en <= 1'b1;
                                    ram_wr_addr <= addr[ADDR_W-1:0];
                                    ram_wr_data <= data[15:0];  // Low 16 bits
                                    if (addr[ADDR_W-1:0] >= seq_prog_len) begin
                                        seq_prog_len <= addr[ADDR_W-1:0] + 1'b1;
                                    end
                                    write_phase <= 2'd1;
                                    addr <= addr + 1; // Next address for high 16 bits
                                end else begin
                                    ram_wr_en <= 1'b1;
                                    ram_wr_addr <= addr[ADDR_W-1:0];
                                    ram_wr_data <= data[31:16]; // High 16 bits
                                    if (addr[ADDR_W-1:0] >= seq_prog_len) begin
                                        seq_prog_len <= addr[ADDR_W-1:0] + 1'b1;
                                    end
                                    write_phase <= 2'd0;
                                    st <= S_IDLE;  // Done with both writes, return to IDLE
                                end
                            end else begin
                                // 32-bit mode (legacy)
                                ram_wr_en <= 1'b1;
                                ram_wr_addr <= addr[ADDR_W-1:0];
                                ram_wr_data <= data[DATA_W-1:0];
                                if (addr[ADDR_W-1:0] >= seq_prog_len) begin
                                    seq_prog_len <= addr[ADDR_W-1:0] + 1'b1;
                                end
                                st <= S_IDLE;
                            end
                            host_state <= 2'd1;
                            // Wait for CS rise before accepting next command
                            if (cs_rise) begin
                                st <= S_IDLE;
                            end
                        end
                        CMD_RUN: begin
                            seq_prog_len <= addr[ADDR_W-1:0];
                            host_state <= 2'd2;
                            // Wait for CS rise to trigger seq_start (handled above)
                            if (cs_rise) begin
                                st <= S_IDLE;
                                write_phase <= 2'd0;
                            end
                        end
                        CMD_READBACK: begin
                            host_state <= 2'd3;
                            st <= S_IDLE;
                        end
                        default: begin
                            host_state <= 2'd0;
                            st <= S_IDLE;
                        end
                    endcase
                end
            endcase
        end
    end

    assign spi_miso = 1'b0;

endmodule
