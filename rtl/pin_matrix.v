/*
 * pin_matrix: 8×8 crossbar with direction, pull, and source selection.
 * Memory-mapped at 0xF100-0xF10F
 * 
 * Each pin can be driven by:
 * - CPU (via memory-mapped PIN_OUT register)
 * - Timer 0-7 NCO output
 * - Timer 0-7 PWM output
 * 
 * Configuration per pin:
 * - DIR: 0=input, 1=output
 * - SEL: 4-bit source select (0=CPU, 1-8=Timer0-7)
 * - PULL: 2-bit (0=none, 1=pull-up, 2=pull-down)
 */
module pin_matrix #(
    parameter NUM_PINS = 8
) (
    input  wire                    clk,
    input  wire                    rst_n,
    // Memory-mapped interface
    input  wire                    wr_en,
    input  wire [3:0]              wr_addr,
    input  wire [15:0]             wr_data,
    output reg  [15:0]             rd_data,
    // CPU pin outputs (from CPU OUT/DIR instructions)
    input  wire [NUM_PINS-1:0]     cpu_pin_out,
    input  wire [NUM_PINS-1:0]     cpu_pin_dir,
    // Timer outputs
    input  wire [NUM_PINS-1:0]     timer_nco_clk,
    input  wire [NUM_PINS-1:0]     timer_pwm_out,
    // External pin interface
    input  wire [NUM_PINS-1:0]     pin_in,
    output reg  [NUM_PINS-1:0]     pin_out,
    output reg  [NUM_PINS-1:0]     pin_oe,
    // Pin event outputs (to timers for capture)
    output reg [NUM_PINS-1:0]      pin_rise,
    output reg [NUM_PINS-1:0]      pin_fall
);

    // Register map
    localparam REG_DIR     = 4'h0; // 8 bits - OR write (set bits)
    localparam REG_SEL     = 4'h1; // 32 bits (4 bits × 8) - low
    localparam REG_SEL_H   = 4'h2; // 32 bits high
    localparam REG_PULL    = 4'h3; // 16 bits (2 bits × 8)
    localparam REG_OUT     = 4'h4; // 8 bits (CPU drives when SEL=0)
    localparam REG_IN      = 4'h5; // 8 bits (read)
    localparam REG_DIR_CLR = 4'h6; // 8 bits - clear bits in DIR

    // Pin configuration
    reg [NUM_PINS-1:0] pin_dir;    // 1=out, 0=in
    reg [3:0] pin_sel [0:NUM_PINS-1]; // 0=CPU, 1-8=Timer0-7
    reg [1:0] pin_pull [0:NUM_PINS-1]; // 0=none, 1=up, 2=down
    reg [NUM_PINS-1:0] pin_in_sync;
    reg [NUM_PINS-1:0] pin_in_prev;

    integer i;

    // Synchronize pin inputs (2-stage for metastability)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pin_in_sync <= {NUM_PINS{1'b1}}; // Pull-up default
            pin_in_prev <= {NUM_PINS{1'b1}};
            pin_rise <= {NUM_PINS{1'b0}};
            pin_fall <= {NUM_PINS{1'b0}};
        end else begin
            pin_in_prev <= pin_in_sync;
            pin_in_sync <= pin_in;
            pin_rise <= pin_in_sync & ~pin_in_prev;
            pin_fall <= ~pin_in_sync & pin_in_prev;
        end
    end

    // Write handling
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pin_dir <= {NUM_PINS{1'b0}};
            for (i = 0; i < NUM_PINS; i = i + 1) begin
                pin_sel[i] <= 4'h0;
                pin_pull[i] <= 2'h0;
            end
        end else if (wr_en) begin
            $display("t=%0t PIN_MATRIX WR: addr=%h data=%h", $time, wr_addr, wr_data);
            case (wr_addr)
                REG_DIR: begin
                    pin_dir <= pin_dir | wr_data[NUM_PINS-1:0];
                    $display("  DIR: pin_dir=%b", pin_dir | wr_data[NUM_PINS-1:0]);
                end
                REG_DIR_CLR: begin
                    pin_dir <= pin_dir & ~wr_data[NUM_PINS-1:0];
                    $display("  DIR_CLR: pin_dir=%b", pin_dir & ~wr_data[NUM_PINS-1:0]);
                end
                REG_SEL: begin
                    pin_sel[0] <= wr_data[3:0];
                    pin_sel[1] <= wr_data[7:4];
                    pin_sel[2] <= wr_data[11:8];
                    pin_sel[3] <= wr_data[15:12];
                    $display("  SEL low: pin_sel[0]=%h pin_sel[1]=%h pin_sel[2]=%h pin_sel[3]=%h", 
                             wr_data[3:0], wr_data[7:4], wr_data[11:8], wr_data[15:12]);
                end
                REG_SEL_H: begin
                    pin_sel[4] <= wr_data[3:0];
                    pin_sel[5] <= wr_data[7:4];
                    pin_sel[6] <= wr_data[11:8];
                    pin_sel[7] <= wr_data[15:12];
                    $display("  SEL high: pin_sel[4]=%h pin_sel[5]=%h pin_sel[6]=%h pin_sel[7]=%h", 
                             wr_data[3:0], wr_data[7:4], wr_data[11:8], wr_data[15:12]);
                end
                REG_PULL: begin
                    for (i = 0; i < NUM_PINS; i = i + 1) begin
                        pin_pull[i] <= wr_data[i*2 +: 2];
                    end
                end
                REG_OUT: begin
                    $display("  OUT write (ignored, direct input)");
                end
                default: begin
                    $display("  UNKNOWN addr=%h", wr_addr);
                end
            endcase
        end
    end

    // Combinational output mux
    always @(*) begin
        pin_out = {NUM_PINS{1'b0}};
        pin_oe  = {NUM_PINS{1'b0}};

        for (i = 0; i < NUM_PINS; i = i + 1) begin
            if (pin_dir[i]) begin // Output mode
                pin_oe[i] = 1'b1;
                case (pin_sel[i])
                    4'h0: pin_out[i] = cpu_pin_out[i];       // CPU
                    4'h1: pin_out[i] = timer_nco_clk[0];     // Timer0 NCO
                    4'h2: pin_out[i] = timer_nco_clk[1];     // Timer1 NCO
                    4'h3: pin_out[i] = timer_nco_clk[2];     // Timer2 NCO
                    4'h4: pin_out[i] = timer_nco_clk[3];     // Timer3 NCO
                    4'h5: pin_out[i] = timer_nco_clk[4];     // Timer4 NCO
                    4'h6: pin_out[i] = timer_nco_clk[5];     // Timer5 NCO
                    4'h7: pin_out[i] = timer_nco_clk[6];     // Timer6 NCO
                    4'h8: pin_out[i] = timer_nco_clk[7];     // Timer7 NCO
                    4'h9: pin_out[i] = timer_pwm_out[0];     // Timer0 PWM
                    4'hA: pin_out[i] = timer_pwm_out[1];     // Timer1 PWM
                    4'hB: pin_out[i] = timer_pwm_out[2];     // Timer2 PWM
                    4'hC: pin_out[i] = timer_pwm_out[3];     // Timer3 PWM
                    4'hD: pin_out[i] = timer_pwm_out[4];     // Timer4 PWM
                    4'hE: pin_out[i] = timer_pwm_out[5];     // Timer5 PWM
                    4'hF: pin_out[i] = timer_pwm_out[6];     // Timer6 PWM
                    default: pin_out[i] = 1'b0;
                endcase
            end else begin // Input mode
                pin_oe[i] = 1'b0;
                pin_out[i] = 1'b0;
            end
        end
        
    end

    // Debug - check pin_sel[2] value
    always @(pin_sel[2]) begin
        $display("t=%0t PIN_MATRIX PIN_SEL[2] CHANGED: pin_sel[2]=%h", $time, pin_sel[2]);
    end

    // Read handling
    always @(*) begin
        case (wr_addr)
            REG_DIR:     rd_data = {8'h00, pin_dir};
            REG_SEL:     rd_data = {pin_sel[3], pin_sel[2], pin_sel[1], pin_sel[0]};
            REG_SEL_H:   rd_data = {pin_sel[7], pin_sel[6], pin_sel[5], pin_sel[4]};
            REG_PULL: begin
                reg [15:0] pull_data;
                for (i = 0; i < NUM_PINS; i = i + 1) pull_data[i*2 +: 2] = pin_pull[i];
                rd_data = pull_data;
            end
            REG_DIR_CLR: rd_data = {8'h00, pin_dir};
            REG_OUT:     rd_data = {8'h00, cpu_pin_out};
            REG_IN:      rd_data = {8'h00, pin_in_sync};
            default:     rd_data = 16'h0000;
        endcase
    end

endmodule
