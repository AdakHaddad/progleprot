/*
 * AXI-Lite Wrapper for Protocol Emulator
 * Maps protocol emulator registers to AXI-Lite slave interface
 * 
 * Address Map (offset from base):
 * 0x00-0x7F: Timer Coprocessor (8 timers × 16 bytes)
 *   0x00 + n*16: Timer n tuning_word[15:0]
 *   0x04 + n*16: Timer n mode[1:0] + compare[13:0]
 *   0x08 + n*16: Timer n capture[15:0]
 *   0x0C + n*16: Timer n counter[15:0]
 * 0x80-0x8F: Pin Matrix (8 pins × 2 bytes)
 *   0x80: Pin direction
 *   0x82: Pin output
 *   0x84: Pin input (read-only)
 *   0x86: Pin OE
 *   0x88: Pin rise events
 *   0x8A: Pin fall events
 * 0x90-0x9F: CPU Debug
 *   0x90: PC
 *   0x92: CPU running/error status
 *   0x94-0xA3: GPRs (16 registers)
 * 0xF0-0xFF: Host Interface / Program RAM control
 *   0xF0: Host state
 *   0xF2: Program length
 *   0xF4: Program RAM write address
 *   0xF6: Program RAM write data
 *   0xF8: Program RAM write enable (pulse)
 *   0xFA: CPU start (pulse)
 */
module axi_lite_protocol_emu #(
    parameter NUM_PINS = 8,
    parameter PROG_DEPTH = 2048,
    parameter PROG_W = 16,
    parameter ADDR_W = 16,
    parameter AXI_ADDR_W = 32,
    parameter AXI_DATA_W = 32
) (
    // AXI-Lite Clock/Reset
    input  wire                    s_axi_aclk,
    input  wire                    s_axi_aresetn,
    
    // AXI-Lite Write Address Channel
    input  wire [AXI_ADDR_W-1:0]   s_axi_awaddr,
    input  wire                    s_axi_awvalid,
    output wire                    s_axi_awready,
    
    // AXI-Lite Write Data Channel
    input  wire [AXI_DATA_W-1:0]   s_axi_wdata,
    input  wire [(AXI_DATA_W/8)-1:0] s_axi_wstrb,
    input  wire                    s_axi_wvalid,
    output wire                    s_axi_wready,
    
    // AXI-Lite Write Response Channel
    output wire [1:0]              s_axi_bresp,
    output wire                    s_axi_bvalid,
    input  wire                    s_axi_bready,
    
    // AXI-Lite Read Address Channel
    input  wire [AXI_ADDR_W-1:0]   s_axi_araddr,
    input  wire                    s_axi_arvalid,
    output wire                    s_axi_arready,
    
    // AXI-Lite Read Data Channel
    output wire [AXI_DATA_W-1:0]   s_axi_rdata,
    output wire [1:0]              s_axi_rresp,
    output wire                    s_axi_rvalid,
    input  wire                    s_axi_rready,
    
    // Protocol Emulator Interface
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire [NUM_PINS-1:0]     pin_in,
    output wire [NUM_PINS-1:0]     pin_out,
    output wire [NUM_PINS-1:0]     pin_oe,
    output wire                    cpu_running,
    output wire                    cpu_error,
    
    // External AXI Master for Program RAM (optional)
    output wire                    ext_ram_wr_en,
    output wire [ADDR_W-1:0]       ext_ram_wr_addr,
    output wire [PROG_W-1:0]       ext_ram_wr_data,
    input  wire                    ext_ram_wr_done
);

    // ------------------------------------------------------------------------
    // AXI-Lite Signal Declarations
    // ------------------------------------------------------------------------
    reg [AXI_ADDR_W-1:0] axi_awaddr_reg;
    reg                  axi_awvalid_reg;
    wire                 axi_awready_int;
    
    reg [AXI_DATA_W-1:0] axi_wdata_reg;
    reg [(AXI_DATA_W/8)-1:0] axi_wstrb_reg;
    reg                  axi_wvalid_reg;
    wire                 axi_wready_int;
    
    reg [1:0]            axi_bresp_reg;
    reg                  axi_bvalid_reg;
    wire                 axi_bready_int;
    
    reg [AXI_ADDR_W-1:0] axi_araddr_reg;
    reg                  axi_arvalid_reg;
    wire                 axi_arready_int;
    
    reg [AXI_DATA_W-1:0] axi_rdata_reg;
    reg [1:0]            axi_rresp_reg;
    reg                  axi_rvalid_reg;
    wire                 axi_rready_int;

    // ------------------------------------------------------------------------
    // Internal Registers
    // ------------------------------------------------------------------------
    // Timer registers (8 timers × 4 registers = 128 bytes = 32 x 32-bit words)
    reg [31:0] timer_regs [0:31];
    
    // Pin matrix registers
    reg [15:0] pin_dir_reg;
    reg [15:0] pin_out_reg;
    reg [15:0] pin_oe_reg;
    
    // CPU debug
    reg [15:0] pc_debug;
    reg        cpu_running_reg;
    reg        cpu_error_reg;
    reg [15:0] gprs [0:15];
    
    // Host interface
    reg [7:0]  host_state_reg;
    reg [15:0] seq_prog_len_reg;
    reg [15:0] ram_wr_addr_reg;
    reg [15:0] ram_wr_data_reg;
    reg        ram_wr_en_reg;
    reg        cpu_start_reg;
    
    // ------------------------------------------------------------------------
    // Protocol Emulator Core Instance
    // ------------------------------------------------------------------------
    wire [ADDR_W-1:0] cpu_prog_addr;
    wire [PROG_W-1:0] cpu_prog_data;
    wire              cpu_timer_wr_en;
    wire [6:0]        cpu_timer_wr_addr;
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
    wire [ADDR_W-1:0] cpu_pc_debug;
    wire [3:0]        dbg_reg_idx;
    wire [15:0]       dbg_reg_data;
    
    wire [NUM_PINS-1:0] timer_nco_clk;
    wire [NUM_PINS-1:0] timer_pwm_out;
    wire [NUM_PINS-1:0] timer_pin_rise;
    wire [NUM_PINS-1:0] timer_pin_fall;
    wire [NUM_PINS-1:0] timer_event;
    wire [NUM_PINS-1:0] matrix_pin_out;
    wire [NUM_PINS-1:0] matrix_pin_oe;
    wire [1:0]          host_state;
    
    reg [NUM_PINS-1:0] cpu_pin_out_reg;
    reg [NUM_PINS-1:0] cpu_pin_dir_reg;
    
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
    
    // Program RAM
    prog_ram #(
        .DEPTH(PROG_DEPTH),
        .WIDTH(PROG_W),
        .ADDR_W(11)
    ) u_prog_ram (
        .clk(clk),
        .rst_n(rst_n),
        .host_wr_en(host_wr_en | ram_wr_en_reg),
        .host_wr_addr(host_wr_en ? host_ram_wr_addr[10:0] : ram_wr_addr_reg[10:0]),
        .host_wr_data(host_wr_en ? host_ram_wr_data : ram_wr_data_reg),
        .seq_rd_addr(cpu_prog_addr[10:0]),
        .seq_rd_data(cpu_prog_data)
    );
    
    // Host interface (internal)
    wire host_ram_wr_en;
    wire [ADDR_W-1:0] host_ram_wr_addr;
    wire [PROG_W-1:0] host_ram_wr_data;
    wire host_seq_start;
    wire [ADDR_W-1:0] host_seq_prog_len;
    
    host_if #(
        .ADDR_W(ADDR_W),
        .DATA_W(PROG_W)
    ) u_host_if (
        .clk(clk),
        .rst_n(rst_n),
        .spi_sck(1'b0),
        .spi_mosi(1'b0),
        .spi_miso(),
        .spi_cs_n(1'b1),
        .ram_wr_en(host_ram_wr_en),
        .ram_wr_addr(host_ram_wr_addr),
        .ram_wr_data(host_ram_wr_data),
        .seq_start(host_seq_start),
        .seq_prog_len(host_seq_prog_len),
        .host_state(host_state)
    );
    
    assign cpu_start = host_seq_start | cpu_start_reg;
    
    // CPU pin register updates
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cpu_pin_out_reg <= 0;
            cpu_pin_dir_reg <= 0;
        end else if (cpu_pin_wr_en) begin
            case (cpu_pin_wr_addr)
                4'h4: cpu_pin_out_reg <= cpu_pin_wr_data[NUM_PINS-1:0];
                4'h0: cpu_pin_dir_reg <= cpu_pin_dir_reg | cpu_pin_wr_data[NUM_PINS-1:0];
            endcase
        end
    end
    
    // ------------------------------------------------------------------------
    // AXI-Lite Write Logic
    // ------------------------------------------------------------------------
    assign axi_awready_int = ~axi_awvalid_reg & ~axi_wvalid_reg;
    assign axi_wready_int = ~axi_awvalid_reg & ~axi_wvalid_reg;
    assign axi_bready_int = 1'b1;
    
    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            axi_awvalid_reg <= 0;
            axi_wvalid_reg <= 0;
            axi_bvalid_reg <= 0;
            axi_bresp_reg <= 2'b00;
        end else begin
            if (axi_awready_int && s_axi_awvalid && s_axi_wvalid) begin
                axi_awaddr_reg <= s_axi_awaddr;
                axi_wdata_reg <= s_axi_wdata;
                axi_wstrb_reg <= s_axi_wstrb;
                axi_awvalid_reg <= 1;
                axi_wvalid_reg <= 1;
                axi_bvalid_reg <= 1;
            end else if (axi_bvalid_reg && s_axi_bready) begin
                axi_bvalid_reg <= 0;
                axi_awvalid_reg <= 0;
                axi_wvalid_reg <= 0;
            end
        end
    end
    
    // Register write on AWVALID & WVALID
    always @(posedge s_axi_aclk) begin
        if (axi_awready_int && s_axi_awvalid && s_axi_wvalid) begin
            case (s_axi_awaddr[7:0])
                // Timer registers (0x00-0x7F)
                8'h00, 8'h04, 8'h08, 8'h0C,
                8'h10, 8'h14, 8'h18, 8'h1C,
                8'h20, 8'h24, 8'h28, 8'h2C,
                8'h30, 8'h34, 8'h38, 8'h3C,
                8'h40, 8'h44, 8'h48, 8'h4C,
                8'h50, 8'h54, 8'h58, 8'h5C,
                8'h60, 8'h64, 8'h68, 8'h6C,
                8'h70, 8'h74, 8'h78, 8'h7C: begin
                    timer_regs[s_axi_awaddr[6:2]] <= s_axi_wdata;
                end
                
                // Pin matrix
                8'h80: pin_dir_reg <= s_axi_wdata[15:0];
                8'h82: pin_out_reg <= s_axi_wdata[15:0];
                8'h86: pin_oe_reg <= s_axi_wdata[15:0];
                
                // Host interface
                8'hF0: host_state_reg <= s_axi_wdata[7:0];
                8'hF2: seq_prog_len_reg <= s_axi_wdata[15:0];
                8'hF4: ram_wr_addr_reg <= s_axi_wdata[15:0];
                8'hF6: ram_wr_data_reg <= s_axi_wdata[15:0];
                8'hF8: ram_wr_en_reg <= s_axi_wdata[0];
                8'hFA: cpu_start_reg <= s_axi_wdata[0];
            endcase
        end
    end
    
    // ------------------------------------------------------------------------
    // AXI-Lite Read Logic
    // ------------------------------------------------------------------------
    assign axi_arready_int = ~axi_arvalid_reg;
    assign axi_rready_int = 1'b1;
    
    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            axi_arvalid_reg <= 0;
            axi_rvalid_reg <= 0;
            axi_rresp_reg <= 2'b00;
            axi_rdata_reg <= 0;
        end else begin
            if (axi_arready_int && s_axi_arvalid) begin
                axi_araddr_reg <= s_axi_araddr;
                axi_arvalid_reg <= 1;
                axi_rvalid_reg <= 1;
                
                case (s_axi_araddr[7:0])
                    // Timer registers
                    8'h00, 8'h04, 8'h08, 8'h0C,
                    8'h10, 8'h14, 8'h18, 8'h1C,
                    8'h20, 8'h24, 8'h28, 8'h2C,
                    8'h30, 8'h34, 8'h38, 8'h3C,
                    8'h40, 8'h44, 8'h48, 8'h4C,
                    8'h50, 8'h54, 8'h58, 8'h5C,
                    8'h60, 8'h64, 8'h68, 8'h6C,
                    8'h70, 8'h74, 8'h78, 8'h7C: begin
                        axi_rdata_reg <= timer_regs[s_axi_araddr[6:2]];
                    end
                    
                    // Pin matrix
                    8'h80: axi_rdata_reg <= {16'h0, pin_dir_reg};
                    8'h82: axi_rdata_reg <= {16'h0, pin_out_reg};
                    8'h84: axi_rdata_reg <= {16'h0, pin_in};
                    8'h86: axi_rdata_reg <= {16'h0, pin_oe_reg};
                    8'h88: axi_rdata_reg <= {24'h0, timer_pin_rise};
                    8'h8A: axi_rdata_reg <= {24'h0, timer_pin_fall};
                    
                    // CPU debug
                    8'h90: axi_rdata_reg <= {16'h0, cpu_pc_debug};
                    8'h92: axi_rdata_reg <= {30'h0, cpu_error_reg, cpu_running_reg};
                    8'h94: axi_rdata_reg <= {16'h0, gprs[0]};
                    8'h98: axi_rdata_reg <= {16'h0, gprs[1]};
                    8'h9C: axi_rdata_reg <= {16'h0, gprs[2]};
                    8'hA0: axi_rdata_reg <= {16'h0, gprs[3]};
                    8'hA4: axi_rdata_reg <= {16'h0, gprs[4]};
                    8'hA8: axi_rdata_reg <= {16'h0, gprs[5]};
                    8'hAC: axi_rdata_reg <= {16'h0, gprs[6]};
                    8'hB0: axi_rdata_reg <= {16'h0, gprs[7]};
                    8'hB4: axi_rdata_reg <= {16'h0, gprs[8]};
                    8'hB8: axi_rdata_reg <= {16'h0, gprs[9]};
                    8'hBC: axi_rdata_reg <= {16'h0, gprs[10]};
                    8'hC0: axi_rdata_reg <= {16'h0, gprs[11]};
                    8'hC4: axi_rdata_reg <= {16'h0, gprs[12]};
                    8'hC8: axi_rdata_reg <= {16'h0, gprs[13]};
                    8'hCC: axi_rdata_reg <= {16'h0, gprs[14]};
                    8'hD0: axi_rdata_reg <= {16'h0, gprs[15]};
                    
                    // Host interface
                    8'hF0: axi_rdata_reg <= {24'h0, host_state};
                    8'hF2: axi_rdata_reg <= {16'h0, seq_prog_len_reg};
                    8'hF4: axi_rdata_reg <= {16'h0, ram_wr_addr_reg};
                    8'hF6: axi_rdata_reg <= {16'h0, ram_wr_data_reg};
                    
                    default: axi_rdata_reg <= 32'hDEADBEEF;
                endcase
            end else if (axi_rvalid_reg && s_axi_rready) begin
                axi_rvalid_reg <= 0;
                axi_arvalid_reg <= 0;
            end
        end
    end
    
    // ------------------------------------------------------------------------
    // Output Assignments
    // ------------------------------------------------------------------------
    assign s_axi_awready = axi_awready_int;
    assign s_axi_wready = axi_wready_int;
    assign s_axi_bresp = axi_bresp_reg;
    assign s_axi_bvalid = axi_bvalid_reg;
    assign s_axi_arready = axi_arready_int;
    assign s_axi_rdata = axi_rdata_reg;
    assign s_axi_rresp = axi_rresp_reg;
    assign s_axi_rvalid = axi_rvalid_reg;
    
    assign pin_out = matrix_pin_out;
    assign pin_oe = matrix_pin_oe;
    assign cpu_running = cpu_running_reg;
    assign cpu_error = cpu_error_reg;
    
    assign ext_ram_wr_en = ram_wr_en_reg;
    assign ext_ram_wr_addr = ram_wr_addr_reg;
    assign ext_ram_wr_data = ram_wr_data_reg;

endmodule
