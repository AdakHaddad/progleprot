/*
 * Basys3 Protocol Emulator Demo
 * Artix-7 XC7A35T @ 100MHz
 * 
 * Connections:
 * - PMOD JA: 8 I/O pins (pin_in/out/oe)
 * - UART: USB-UART bridge (host firmware loading)
 * - LEDs: Status (cpu_running, cpu_error, pin activity)
 * - BTN0: Reset
 * - SW[7:0]: Optional pin input override
 */
module basys3_protocol_emu #(
    parameter NUM_PINS = 8,
    parameter PROG_DEPTH = 2048,
    parameter PROG_W = 16,
    parameter ADDR_W = 16,
    parameter CLK_FREQ_HZ = 100_000_000,
    parameter TARGET_FREQ_HZ = 50_000_000
) (
    input  wire                    clk_100mhz,    // Basys3 100MHz clock
    input  wire                    btn0,          // Reset (active high)
    input  wire [15:0]             sw,            // Switches
    output wire [15:0]             led,           // LEDs
    
    // PMOD JA (8 pins) - main I/O
    inout  wire [7:0]              ja,
    
    // PMOD JB (optional - for AXI I2S or extra I/O)
    inout  wire [7:0]              jb,
    
    // UART (USB-UART bridge)
    input  wire                    uart_rx,
    output wire                    uart_tx,
    
    // SPI flash (optional - for firmware storage)
    output wire                    spi_cs_n,
    output wire                    spi_sck,
    output wire                    spi_mosi,
    input  wire                    spi_miso
);

    // ------------------------------------------------------------------------
    // Clock Generation (100MHz -> 50MHz)
    // ------------------------------------------------------------------------
    reg clk_50mhz;
    always @(posedge clk_100mhz) begin
        clk_50mhz <= ~clk_50mhz;
    end
    
    wire clk = clk_50mhz;
    wire rst_n = ~btn0;

    // ------------------------------------------------------------------------
    // PMOD IO Buffers
    // ------------------------------------------------------------------------
    wire [NUM_PINS-1:0] pmod_ja_in;
    wire [NUM_PINS-1:0] pmod_ja_out;
    wire [NUM_PINS-1:0] pmod_ja_oe;
    
    genvar i;
    generate
        for (i = 0; i < NUM_PINS; i = i + 1) begin : pmod_io
            IOBUF iobuf_inst (
                .IO  (ja[i]),
                .O   (pmod_ja_in[i]),
                .I   (pmod_ja_out[i]),
                .T   (~pmod_ja_oe[i])
            );
        end
    endgenerate

    // ------------------------------------------------------------------------
    // UART Host Interface (for firmware loading via USB-UART)
    // ------------------------------------------------------------------------
    reg [ADDR_W-1:0]   host_wr_addr;
    reg [PROG_W-1:0]   host_wr_data;
    reg                host_wr_en;
    reg                host_seq_start;
    reg [ADDR_W-1:0]   host_seq_prog_len;
    wire [1:0]         host_state;
    
    // Simple UART receiver for host commands
    // Format: [CMD:8][ADDR_H:8][ADDR_L:8][DATA_H:8][DATA_L:8]
    // CMD: 0x01 = Write RAM, 0x02 = Start CPU, 0x03 = Read Reg
    
    wire [7:0] uart_rx_data;
    wire       uart_rx_valid;
    wire       uart_tx_ready;
    
    uart_rx #(
        .CLK_FREQ_HZ(TARGET_FREQ_HZ),
        .BAUD_RATE(115200)
    ) u_uart_rx (
        .clk(clk),
        .rst_n(rst_n),
        .rx(uart_rx),
        .data(uart_rx_data),
        .valid(uart_rx_valid)
    );
    
    uart_tx #(
        .CLK_FREQ_HZ(TARGET_FREQ_HZ),
        .BAUD_RATE(115200)
    ) u_uart_tx (
        .clk(clk),
        .rst_n(rst_n),
        .data(8'h00),
        .valid(1'b0),
        .tx(uart_tx),
        .ready(uart_tx_ready)
    );
    
    // UART command parser
    reg [2:0] uart_state;
    reg [7:0] uart_cmd;
    reg [15:0] uart_addr;
    reg [15:0] uart_data;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_state <= 0;
            host_wr_en <= 0;
            host_wr_addr <= 0;
            host_wr_data <= 0;
            host_seq_start <= 0;
            host_seq_prog_len <= 0;
        end else begin
            host_wr_en <= 0;
            host_seq_start <= 0;
            
            if (uart_rx_valid) begin
                case (uart_state)
                    0: begin // CMD
                        uart_cmd <= uart_rx_data;
                        uart_state <= 1;
                    end
                    1: begin // ADDR_H
                        uart_addr[15:8] <= uart_rx_data;
                        uart_state <= 2;
                    end
                    2: begin // ADDR_L
                        uart_addr[7:0] <= uart_rx_data;
                        uart_state <= 3;
                    end
                    3: begin // DATA_H
                        uart_data[15:8] <= uart_rx_data;
                        uart_state <= 4;
                    end
                    4: begin // DATA_L
                        uart_data[7:0] <= uart_rx_data;
                        uart_state <= 0;
                        
                        case (uart_cmd)
                            8'h01: begin // Write RAM
                                host_wr_en <= 1;
                                host_wr_addr <= uart_addr;
                                host_wr_data <= uart_data;
                            end
                            8'h02: begin // Start CPU
                                host_seq_start <= 1;
                                host_seq_prog_len <= uart_data;
                            end
                            8'h03: begin // Read register (TODO: implement response)
                            end
                        endcase
                    end
                endcase
            end
        end
    end

    // ------------------------------------------------------------------------
    // Protocol Emulator Core
    // ------------------------------------------------------------------------
    wire [NUM_PINS-1:0] pin_out;
    wire [NUM_PINS-1:0] pin_oe;
    wire                cpu_running;
    wire                cpu_error;
    wire [15:0]         dbg_reg_data;
    wire [3:0]          dbg_reg_idx;
    
    emu_top #(
        .NUM_PINS(NUM_PINS),
        .PROG_DEPTH(PROG_DEPTH),
        .PROG_W(PROG_W),
        .ADDR_W(ADDR_W)
    ) u_emu_top (
        .clk(clk),
        .rst_n(rst_n),
        .pin_in(pmod_ja_in),
        .pin_out(pmod_ja_out),
        .pin_oe(pmod_ja_oe),
        .spi_sck(host_wr_addr[0]),      // Not used with UART host - repurpose for debug
        .spi_mosi(host_wr_data[0]),
        .spi_miso(),
        .spi_cs_n(1'b1),
        .cpu_running(cpu_running),
        .cpu_error(cpu_error),
        .dbg_reg_idx(dbg_reg_idx),
        .dbg_reg_data(dbg_reg_data)
    );
    
    // Override host interface with UART
    // (Need to modify emu_top to accept external host interface)
    // For now, connect host_if internally and use UART for loading
    
    // ------------------------------------------------------------------------
    // Status LEDs
    // ------------------------------------------------------------------------
    // LED[0] = CPU running
    // LED[1] = CPU error
    // LED[7:2] = Pin activity (output)
    // LED[15:8] = Pin input state
    assign led[0] = cpu_running;
    assign led[1] = cpu_error;
    assign led[7:2] = pmod_ja_out[5:0];
    assign led[15:8] = pmod_ja_in;
    
    // Debug register select via switches
    assign dbg_reg_idx = sw[3:0];

    // ------------------------------------------------------------------------
    // Optional: AXI-Lite Interface for Custom Modules (JX PMOD)
    // ------------------------------------------------------------------------
    // JX PMOD can connect to custom AXI I2S module
    // Expose AXI-Lite signals on JB PMOD
    wire        axi_aclk = clk;
    wire        axi_aresetn = rst_n;
    wire [31:0] axi_awaddr;
    wire        axi_awvalid;
    wire        axi_awready;
    wire [31:0] axi_wdata;
    wire [3:0]  axi_wstrb;
    wire        axi_wvalid;
    wire        axi_wready;
    wire [1:0]  axi_bresp;
    wire        axi_bvalid;
    wire        axi_bready;
    wire [31:0] axi_araddr;
    wire        axi_arvalid;
    wire        axi_arready;
    wire [31:0] axi_rdata;
    wire [1:0]  axi_rresp;
    wire        axi_rvalid;
    wire        axi_rready;
    
    // For now, tie off AXI (connect your AXI I2S here)
    assign axi_awready = 1'b0;
    assign axi_wready = 1'b0;
    assign axi_bvalid = 1'b0;
    assign axi_bresp = 2'b00;
    assign axi_arready = 1'b0;
    assign axi_rvalid = 1'b0;
    assign axi_rdata = 32'h0;
    assign axi_rresp = 2'b00;

endmodule


// -----------------------------------------------------------------------------
// Simple UART RX (115200 baud)
// -----------------------------------------------------------------------------
module uart_rx #(
    parameter CLK_FREQ_HZ = 50_000_000,
    parameter BAUD_RATE = 115200
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        valid
);
    localparam DIVISOR = CLK_FREQ_HZ / BAUD_RATE;
    localparam DIV_W = $clog2(DIVISOR);
    
    reg [DIV_W-1:0] baud_cnt;
    reg [3:0] bit_idx;
    reg [1:0] state;
    reg rx_d1, rx_d2;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_d1 <= 1'b1;
            rx_d2 <= 1'b1;
            state <= 0;
            baud_cnt <= 0;
            bit_idx <= 0;
            data <= 0;
            valid <= 0;
        end else begin
            rx_d1 <= rx;
            rx_d2 <= rx_d1;
            valid <= 0;
            
            case (state)
                0: begin // Wait for start bit
                    if (!rx_d2 && rx_d1) begin // Falling edge
                        state <= 1;
                        baud_cnt <= 0;
                        bit_idx <= 0;
                    end
                end
                1: begin // Receive 8 data bits
                    if (baud_cnt == DIVISOR - 1) begin
                        baud_cnt <= 0;
                        data[bit_idx] <= rx_d2;
                        if (bit_idx == 7)
                            state <= 2;
                        else
                            bit_idx <= bit_idx + 1;
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end
                2: begin // Stop bit
                    if (baud_cnt == DIVISOR - 1) begin
                        state <= 0;
                        valid <= 1;
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end
            endcase
        end
    end
endmodule


// -----------------------------------------------------------------------------
// Simple UART TX (115200 baud)
// -----------------------------------------------------------------------------
module uart_tx #(
    parameter CLK_FREQ_HZ = 50_000_000,
    parameter BAUD_RATE = 115200
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] data,
    input  wire       valid,
    output reg        tx,
    output reg        ready
);
    localparam DIVISOR = CLK_FREQ_HZ / BAUD_RATE;
    localparam DIV_W = $clog2(DIVISOR);
    
    reg [DIV_W-1:0] baud_cnt;
    reg [3:0] bit_idx;
    reg [1:0] state;
    reg [9:0] shift_reg; // start + 8 data + stop
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= 0;
            baud_cnt <= 0;
            bit_idx <= 0;
            shift_reg <= 10'h3FF;
            tx <= 1'b1;
            ready <= 1'b1;
        end else begin
            case (state)
                0: begin // Idle
                    tx <= 1'b1;
                    ready <= 1'b1;
                    if (valid) begin
                        shift_reg <= {1'b1, data, 1'b0}; // stop, data, start
                        state <= 1;
                        baud_cnt <= 0;
                        bit_idx <= 0;
                        ready <= 1'b0;
                    end
                end
                1: begin // Transmit
                    tx <= shift_reg[bit_idx];
                    if (baud_cnt == DIVISOR - 1) begin
                        baud_cnt <= 0;
                        if (bit_idx == 9)
                            state <= 0;
                        else
                            bit_idx <= bit_idx + 1;
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end
            endcase
        end
    end
endmodule
