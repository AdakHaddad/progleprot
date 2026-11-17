/*
 * Protocol Emulator Core - Tiny Tapeout IHP wrapper
 * 
 * A reprogrammable timing engine for protocol emulation.
 * Firmware loaded via SPI host interface implements any protocol.
 * 
 * Pin mapping:
 * ui_in[7:0]   = pins_in[7:0]      (8 bidirectional protocol pins)
 * uio_in[0]    = SPI SCK           (host interface clock)
 * uio_in[1]    = SPI MOSI          (host interface data in)
 * uio_in[2]    = SPI CS_N          (host interface chip select, active low)
 * uio_in[3]    = reserved
 * uio_in[4]    = reserved
 * uio_in[5]    = reserved
 * uio_in[6]    = reserved
 * uio_in[7]    = reserved
 * 
 * uo_out[7:0]  = pins_out[7:0]     (pin outputs when OE=1)
 * uio_out[0]   = SPI MISO          (host interface data out)
 * uio_out[1]   = sequencer done
 * uio_out[2]   = sequencer error
 * uio_out[3]   = host state[0]
 * uio_out[4]   = host state[1]
 * uio_out[5]   = reserved
 * uio_out[6]   = reserved
 * uio_out[7]   = reserved
 * uio_oe[7:0]  = pin_oe[7:0] | {7'b0, 1'b1}  (MISO always driven)
 */

module tt_um_protocol_emu (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high)
    input  wire       ena,      // always 1 when the design is powered
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    // ------------------------------------------------------------------------
    // Parameters
    // ------------------------------------------------------------------------
    localparam NUM_PINS = 8;
    localparam PROG_DEPTH = 256;
    localparam PROG_W = 32;
    localparam ADDR_W = 8;

    // ------------------------------------------------------------------------
    // Signal declarations
    // ------------------------------------------------------------------------
    wire [NUM_PINS-1:0] pin_in;
    wire [NUM_PINS-1:0] pin_out;
    wire [NUM_PINS-1:0] pin_oe;
    
    // Host interface
    wire                host_ram_wr_en;
    wire [ADDR_W-1:0]   host_ram_wr_addr;
    wire [PROG_W-1:0]   host_ram_wr_data;
    wire                seq_start;
    wire [ADDR_W-1:0]   seq_prog_len;
    wire [1:0]          host_state;

    // Sequencer
    wire [ADDR_W-1:0]   seq_prog_addr;
    wire [PROG_W-1:0]   seq_prog_data;
    wire                seq_done;
    wire                seq_error;
    wire [7:0]          seq_pc;

    // ------------------------------------------------------------------------
    // Pin I/O handling (bidirectional)
    // ------------------------------------------------------------------------
    assign pin_in = ui_in;
    assign uo_out = pin_oe ? pin_out : {NUM_PINS{1'b0}}; // Output when OE=1, else 0

    // ------------------------------------------------------------------------
    // Host Interface (SPI slave on uio_in)
    // ------------------------------------------------------------------------
    wire spi_sck  = uio_in[0];
    wire spi_mosi = uio_in[1];
    wire spi_cs_n = uio_in[2];
    wire spi_miso;

    host_if #(
        .ADDR_W(ADDR_W),
        .DATA_W(PROG_W)
    ) u_host_if (
        .clk(clk),
        .rst_n(rst_n),
        .spi_sck(spi_sck),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .spi_cs_n(spi_cs_n),
        .ram_wr_en(host_ram_wr_en),
        .ram_wr_addr(host_ram_wr_addr),
        .ram_wr_data(host_ram_wr_data),
        .seq_start(seq_start),
        .seq_prog_len(seq_prog_len),
        .host_state(host_state)
    );

    // ------------------------------------------------------------------------
    // Program RAM (dual port: host write, sequencer read)
    // ------------------------------------------------------------------------
    prog_ram #(
        .DEPTH(PROG_DEPTH),
        .WIDTH(PROG_W),
        .ADDR_W(ADDR_W)
    ) u_prog_ram (
        .clk(clk),
        .rst_n(rst_n),
        .host_wr_en(host_ram_wr_en),
        .host_wr_addr(host_ram_wr_addr),
        .host_wr_data(host_ram_wr_data),
        .seq_rd_addr(seq_prog_addr),
        .seq_rd_data(seq_prog_data)
    );

    // ------------------------------------------------------------------------
    // Sequencer (protocol timing engine)
    // ------------------------------------------------------------------------
    pdis_sequencer #(
        .PROG_DEPTH(PROG_DEPTH),
        .PROG_W(PROG_W),
        .NUM_PINS(NUM_PINS)
    ) u_sequencer (
        .clk(clk),
        .rst_n(rst_n),
        .prog_addr(seq_prog_addr),
        .prog_data(seq_prog_data),
        .prog_valid(1'b1),
        .prog_len(seq_prog_len),
        .pin_in(pin_in),
        .pin_out(pin_out),
        .pin_oe(pin_oe),
        .start(seq_start),
        .done(seq_done),
        .error(seq_error),
        .pc(seq_pc)
    );

    // ------------------------------------------------------------------------
    // Output mapping
    // ------------------------------------------------------------------------
    assign uio_out = {3'b0, host_state, seq_error, seq_done, 1'b0, spi_miso};
    assign uio_oe  = {pin_oe[7:1], 1'b1}; // MISO (uio_out[0]) always driven

    // ------------------------------------------------------------------------
    // Unused tie-off
    // ------------------------------------------------------------------------
    wire _unused = &{ena, 1'b0, seq_pc};

endmodule
