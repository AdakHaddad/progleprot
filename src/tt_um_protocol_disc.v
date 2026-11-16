/*
 * Protocol Discovery Core - Tiny Tapeout IHP wrapper
 * 
 * Maps the m6_top protocol discovery core to the TT 8x4 tile interface.
 * 
 * Pin mapping:
 * ui_in[7:0]   = pins_in[7:0]      (8 protocol signal inputs to monitor)
 * uio_in[0]    = clear             (active high reset of internal state)
 * uio_in[1]    = scan_start        (start histogram scan / fingerprint match)
 * uio_in[2]    = replay_start      (start sequencer replay)
 * uio_in[3]    = enc_mode_ch0[0]   (encoding mode for SPI data line, bit 0)
 * uio_in[4]    = enc_mode_ch0[1]   (encoding mode for SPI data line, bit 1)
 * uio_in[5]    = stuff_after_ch0[0] (bit stuffing threshold, bit 0)
 * uio_in[6]    = stuff_after_ch0[1] (bit stuffing threshold, bit 1)
 * uio_in[7]    = stuff_after_ch0[2] (bit stuffing threshold, bit 2)
 * 
 * uo_out[7:0]  = {list_done, ambiguous, result_valid, replay_done, 
 *                 replay_error, scan_done, idle, 1'b0} (key status)
 * uio_out[7:0] = {result_proto[3:0], result_rank[3:0]} (top protocol + rank)
 * uio_oe[7:0]  = 8'hFF (all outputs enabled)
 * 
 * Note: Full debug interface (pin_roles, result_conf, peak_idx, etc.) 
 * available via internal testbench or future UART debug extension.
 */

`default_nettype none

module tt_um_protocol_disc (
    input  wire [7:0] ui_in,    // Dedicated inputs - 8 protocol pins
    output wire [7:0] uo_out,   // Dedicated outputs - status flags
    input  wire [7:0] uio_in,   // IOs: Input path - control signals
    output wire [7:0] uio_out,  // IOs: Output path - protocol ID + rank
    output wire [7:0] uio_oe,   // IOs: Enable path (active high)
    input  wire       ena,      // always 1 when the design is powered
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    // ------------------------------------------------------------------------
    // Parameter mapping
    // ------------------------------------------------------------------------
    localparam NUM_PINS = 8;
    localparam CNT_W = 16;
    localparam FRAC = 1;
    localparam BIN_W = 8;
    localparam IDX_W = $clog2(CNT_W) + FRAC;
    localparam N_COLLECT = 1024;
    localparam MAX_PRINTS = 16;
    localparam MAX_PATTERN_BITS = 64;
    localparam FRAME_BITS = 32;
    localparam MAX_RESULTS = 8;
    localparam PROG_DEPTH = 256;
    localparam PROG_W = 32;

    // ------------------------------------------------------------------------
    // Input signal mapping
    // ------------------------------------------------------------------------
    wire [NUM_PINS-1:0] pins_in = ui_in;
    wire                clear = uio_in[0];
    wire                scan_start = uio_in[1];
    wire                replay_start = uio_in[2];
    wire [1:0]          enc_mode_ch0 = uio_in[4:3];
    wire [3:0]          stuff_after_ch0 = {1'b0, uio_in[7:5]}; // bit 3 tied to 0

    // ------------------------------------------------------------------------
    // Core instance
    // ------------------------------------------------------------------------
    wire [NUM_PINS*3-1:0] pin_roles;
    wire [NUM_PINS-1:0]   role_valid;
    wire                  result_valid;
    wire [3:0]            result_proto;
    wire [7:0]            result_conf;
    wire [3:0]            result_rank;
    wire                  list_done;
    wire                  ambiguous;
    wire                  replay_done;
    wire                  replay_error;
    wire                  idle;
    wire [IDX_W-1:0]      peak_idx;
    wire [BIN_W-1:0]      peak_count;
    wire                  scan_done;
    wire [7:0]            prog_len;
    wire [7:0]            seq_pc;

    m6_top #(
        .CNT_W(CNT_W),
        .FRAC(FRAC),
        .BIN_W(BIN_W),
        .IDX_W(IDX_W),
        .NUM_PINS(NUM_PINS),
        .N_COLLECT(N_COLLECT),
        .MAX_PRINTS(MAX_PRINTS),
        .MAX_PATTERN_BITS(MAX_PATTERN_BITS),
        .FRAME_BITS(FRAME_BITS),
        .MAX_RESULTS(MAX_RESULTS),
        .PROG_DEPTH(PROG_DEPTH),
        .PROG_W(PROG_W)
    ) u_core (
        .clk(clk),
        .rst_n(rst_n),
        .pins_in(pins_in),
        .clear(clear),
        .scan_start(scan_start),
        .replay_start(replay_start),
        .enc_mode_ch0(enc_mode_ch0),
        .stuff_after_ch0(stuff_after_ch0),
        .pin_roles(pin_roles),
        .role_valid(role_valid),
        .result_valid(result_valid),
        .result_proto(result_proto),
        .result_conf(result_conf),
        .result_rank(result_rank),
        .list_done(list_done),
        .ambiguous(ambiguous),
        .replay_done(replay_done),
        .replay_error(replay_error),
        .idle(idle),
        .peak_idx(peak_idx),
        .peak_count(peak_count),
        .scan_done(scan_done),
        .prog_len(prog_len),
        .seq_pc(seq_pc)
    );

    // ------------------------------------------------------------------------
    // Output mapping
    // ------------------------------------------------------------------------
    // uo_out: key status flags (8 bits)
    assign uo_out = {
        list_done,        // [7] ranked list complete
        ambiguous,        // [6] ambiguous result (tie/low confidence)
        result_valid,     // [5] new protocol result available
        replay_done,      // [4] sequencer replay complete
        replay_error,     // [3] sequencer error
        scan_done,        // [2] histogram scan complete
        idle,             // [1] all input pins idle
        1'b0              // [0] reserved
    };

    // uio_out: top protocol ID + rank (8 bits)
    assign uio_out = {result_proto, result_rank};

    // uio_oe: all outputs enabled
    assign uio_oe = 8'hFF;

    // ------------------------------------------------------------------------
    // Unused signal tie-off (prevents warnings)
    // ------------------------------------------------------------------------
    wire _unused = &{ena, 1'b0, 
        pin_roles, role_valid, result_conf, peak_idx, peak_count, prog_len, seq_pc};

endmodule

`default_nettype wire
