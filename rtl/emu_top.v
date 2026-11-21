/*
 * emu_top: Integrated Protocol Emulator Core
 * CPU + Timer Coprocessor + Pin Matrix + Program Memory + Host Interface
 * Memory Map:
 *   0x0000-0x0FFF: Program RAM (4KB) - active bank
 *   0x1000-0x17FF: Boot ROM (2KB)
 *   0xF000-0xF07F: Timer Coprocessor (8 timers × 16 bytes = 128 bytes, 7 bits)
 *   0xF100-0xF10F: Pin Matrix
 *   0xF200-0xF207: Host Interface
 */
module emu_top #(
    parameter NUM_PINS = 8,
    parameter PROG_DEPTH = 2048,  // 4KB = 2048 × 16-bit
    parameter PROG_W = 16,
    parameter ADDR_W = 16
) (
    input  wire                    clk,
    input  wire                    rst_n,
    // External pins
    input  wire [NUM_PINS-1:0]     pin_in,
    output wire [NUM_PINS-1:0]     pin_out,
    output wire [NUM_PINS-1:0]     pin_oe,
    // Host SPI interface
    input  wire                    spi_sck,
    input  wire                    spi_mosi,
    output wire                    spi_miso,
    input  wire                    spi_cs_n,
    // Status
    output wire                    cpu_running,
    output wire                    cpu_error,
    // Debug
    input  wire [3:0]              dbg_reg_idx,
    output wire [15:0]             dbg_reg_data
);

    // ------------------------------------------------------------------------
    // Internal signals
    // ------------------------------------------------------------------------
    
    // CPU interface
    wire [ADDR_W-1:0] cpu_prog_addr;
    wire [PROG_W-1:0] cpu_prog_data;
    wire              cpu_timer_wr_en;
    wire [6:0]        cpu_timer_wr_addr;  // 7 bits for timer (8 timers × 16 bytes)
    wire [15:0]       cpu_timer_wr_data;
    wire [15:0]       cpu_timer_rd_data;
    wire              cpu_pin_wr_en;
    wire [3:0]        cpu_pin_wr_addr;
    wire [15:0]       cpu_pin_wr_data;
    wire [15:0]       cpu_pin_rd_data;
    wire              cpu_host_wr_en;
    wire [3:0]        cpu_host_wr_addr;
    wire [15:0]       cpu_host_wr_data;
    wire [15:0]       cpu_host_rd_data;
    wire              cpu_start;
    wire              cpu_done;
    wire              cpu_err;

    // Debug outputs from CPU
    wire [ADDR_W-1:0]  cpu_pc_debug;

    // Timer coprocessor
    wire [NUM_PINS-1:0] timer_nco_clk;
    wire [NUM_PINS-1:0] timer_pwm_out;
    wire [NUM_PINS-1:0] timer_pin_rise;
    wire [NUM_PINS-1:0] timer_pin_fall;
    wire [NUM_PINS-1:0] timer_event;

    // Pin matrix
    wire [NUM_PINS-1:0] matrix_pin_out;
    wire [NUM_PINS-1:0] matrix_pin_oe;

    // Host interface
    wire                host_ram_wr_en;
    wire [ADDR_W-1:0]   host_ram_wr_addr;
    wire [PROG_W-1:0]   host_ram_wr_data;
    wire                host_seq_start;
    wire [ADDR_W-1:0]   host_seq_prog_len;
    wire [1:0]          host_state;

    // Program memory
    wire [ADDR_W-1:0]   prog_rd_addr;
    wire [PROG_W-1:0]   prog_rd_data;

    // CPU pin outputs (from custom instructions)
    reg [NUM_PINS-1:0] cpu_pin_out_reg;
    reg [NUM_PINS-1:0] cpu_pin_dir_reg;

    // ------------------------------------------------------------------------
    // CPU Core
    // ------------------------------------------------------------------------
    cpu_core #(
        .ADDR_W(ADDR_W),
        .DATA_W(PROG_W)
    ) u_cpu (
        .clk(clk),
        .rst_n(rst_n),
        .prog_addr(cpu_prog_addr),
        .prog_data(cpu_prog_data),
        .timer_wr_en(cpu_timer_wr_en),
        .timer_wr_addr(cpu_timer_wr_addr),
        .timer_wr_data(cpu_timer_wr_data),
        .timer_rd_data(cpu_timer_rd_data),
        .pin_wr_en(cpu_pin_wr_en),
        .pin_wr_addr(cpu_pin_wr_addr),
        .pin_wr_data(cpu_pin_wr_data),
        .pin_rd_data(cpu_pin_rd_data),
        .host_wr_en(cpu_host_wr_en),
        .host_wr_addr(cpu_host_wr_addr),
        .host_wr_data(cpu_host_wr_data),
        .host_rd_data(cpu_host_rd_data),
        .cpu_start(cpu_start),
        .cpu_done(cpu_done),
        .cpu_error(cpu_err),
        .pc_debug(cpu_pc_debug),
        .dbg_reg_idx(dbg_reg_idx),
        .dbg_reg_data(dbg_reg_data)
    );

    // CPU pin register updates (from custom instructions)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cpu_pin_out_reg <= {NUM_PINS{1'b0}};
            cpu_pin_dir_reg <= {NUM_PINS{1'b0}};
        end else if (cpu_pin_wr_en) begin
            case (cpu_pin_wr_addr)
                4'h4: cpu_pin_out_reg <= cpu_pin_wr_data[NUM_PINS-1:0]; // REG_OUT
                4'h0: cpu_pin_dir_reg <= cpu_pin_dir_reg | cpu_pin_wr_data[NUM_PINS-1:0]; // REG_DIR (OR)
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // Timer Coprocessor
    // ------------------------------------------------------------------------
    timer_coproc #(
        .NUM_TIMERS(NUM_PINS)
    ) u_timers (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(cpu_timer_wr_en),
        .wr_addr(cpu_timer_wr_addr),
        .wr_data(cpu_timer_wr_data),
        .rd_data(cpu_timer_rd_data),
        .pin_rise(timer_pin_rise),
        .pin_fall(timer_pin_fall),
        .nco_clk_out(timer_nco_clk),
        .timer_event(timer_event)
    );

    // ------------------------------------------------------------------------
    // Pin Matrix
    // ------------------------------------------------------------------------
    pin_matrix #(
        .NUM_PINS(NUM_PINS)
    ) u_pin_matrix (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(cpu_pin_wr_en),
        .wr_addr(cpu_pin_wr_addr),
        .wr_data(cpu_pin_wr_data),
        .rd_data(cpu_pin_rd_data),
        .cpu_pin_out(cpu_pin_out_reg),
        .cpu_pin_dir(cpu_pin_dir_reg),
        .timer_nco_clk(timer_nco_clk),
        .timer_pwm_out(timer_pwm_out),
        .pin_in(pin_in),
        .pin_out(matrix_pin_out),
        .pin_oe(matrix_pin_oe),
        .pin_rise(timer_pin_rise),
        .pin_fall(timer_pin_fall)
    );

    // ------------------------------------------------------------------------
    // Host Interface (SPI Slave)
    // ------------------------------------------------------------------------
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
        .seq_start(host_seq_start),
        .seq_prog_len(host_seq_prog_len),
        .host_state(host_state)
    );

    // ------------------------------------------------------------------------
    // Program Memory (using prog_ram module with block RAM inference)
    // ------------------------------------------------------------------------
    prog_ram #(
        .DEPTH(PROG_DEPTH),
        .WIDTH(PROG_W),
        .ADDR_W(11)  // 2048 = 2^11
    ) u_prog_ram (
        .clk(clk),
        .rst_n(rst_n),
        .host_wr_en(host_ram_wr_en),
        .host_wr_addr(host_ram_wr_addr[10:0]),
        .host_wr_data(host_ram_wr_data),
        .seq_rd_addr(cpu_prog_addr[10:0]),
        .seq_rd_data(prog_rd_data)
    );

    assign cpu_prog_data = prog_rd_data;

    // Connect host seq_start to CPU start
    assign cpu_start = host_seq_start;

    // ------------------------------------------------------------------------
    // Outputs
    // ------------------------------------------------------------------------
    assign pin_out = matrix_pin_out;
    assign pin_oe  = matrix_pin_oe;
    assign cpu_running = !cpu_done && cpu_start;
    assign cpu_error = cpu_err;

endmodule
