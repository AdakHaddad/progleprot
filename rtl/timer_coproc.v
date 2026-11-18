/*
 * timer_coproc: 8-channel timer coprocessor with NCO frequency synthesis.
 * Each channel: 24-bit NCO, 16-bit counter, capture, compare, events.
 * Memory-mapped at 0xF000-0xF07F (8 timers × 16 bytes)
 */
module timer_coproc #(
    parameter NUM_TIMERS = 8
) (
    input  wire                    clk,
    input  wire                    rst_n,
    // Memory-mapped interface
    input  wire                    wr_en,
    input  wire [3:0]              wr_addr,
    input  wire [15:0]             wr_data,
    output reg  [15:0]             rd_data,
    // Pin event inputs (from pin matrix)
    input  wire [NUM_TIMERS-1:0]   pin_rise,
    input  wire [NUM_TIMERS-1:0]   pin_fall,
    // NCO clock outputs (to pin matrix)
    output reg [NUM_TIMERS-1:0]    nco_clk_out,
    // Event outputs (to CPU WAITE)
    output reg [NUM_TIMERS-1:0]    timer_event
);

    // Register offsets per timer
    localparam REG_TUNING   = 4'h0; // 24-bit: [1:0] + next reg
    localparam REG_TUNING_H = 4'h1; // 24-bit high 16 bits
    localparam REG_COUNTER  = 4'h2; // 16-bit
    localparam REG_CAPTURE  = 4'h3; // 16-bit
    localparam REG_COMPARE  = 4'h4; // 16-bit
    localparam REG_MODE     = 4'h5; // 8-bit
    localparam REG_EV_EN    = 4'h6; // 8-bit
    localparam REG_EV_ST    = 4'h7; // 8-bit (read clears)

    // Timer modes
    localparam MODE_OFF       = 4'h0;
    localparam MODE_COUNT_UP  = 4'h1;
    localparam MODE_COUNT_DOWN= 4'h2;
    localparam MODE_NCO_CLK   = 4'h3;
    localparam MODE_NCO_VAR   = 4'h4;
    localparam MODE_PWM       = 4'h5;
    localparam MODE_CAPTURE   = 4'h6;
    localparam MODE_MEASURE   = 4'h7;

    // Event enable bits
    localparam EV_CMP_MATCH   = 1;
    localparam EV_OVERFLOW    = 2;
    localparam EV_PIN_RISE    = 4;
    localparam EV_PIN_FALL    = 8;
    localparam EV_PIN_BOTH    = 12;
    localparam EV_NCO_TOGGLE  = 16;

    // Per-timer state
    reg [23:0] tuning_word [0:NUM_TIMERS-1];
    reg [23:0] phase_acc   [0:NUM_TIMERS-1];
    reg [15:0] counter     [0:NUM_TIMERS-1];
    reg [15:0] capture     [0:NUM_TIMERS-1];
    reg [15:0] compare     [0:NUM_TIMERS-1];
    reg [7:0]  mode        [0:NUM_TIMERS-1];
    reg [7:0]  ev_enable   [0:NUM_TIMERS-1];
    reg [7:0]  ev_status   [0:NUM_TIMERS-1];
    reg [15:0] prev_counter [0:NUM_TIMERS-1];
    reg        pin_prev    [0:NUM_TIMERS-1];

    integer i;

    // Write handling
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_TIMERS; i = i + 1) begin
                tuning_word[i] <= 24'h0;
                phase_acc[i] <= 24'h0;
                counter[i] <= 16'h0;
                capture[i] <= 16'h0;
                compare[i] <= 16'h0;
                mode[i] <= 8'h0;
                ev_enable[i] <= 8'h0;
                ev_status[i] <= 8'h0;
                prev_counter[i] <= 16'h0;
                pin_prev[i] <= 1'b0;
            end
            nco_clk_out <= {NUM_TIMERS{1'b0}};
            timer_event <= {NUM_TIMERS{1'b0}};
        end else begin
            // Default: clear event outputs
            timer_event <= {NUM_TIMERS{1'b0}};

            // Handle writes
            if (wr_en) begin
                case (wr_addr[1:0])
                    REG_TUNING: begin
                        tuning_word[wr_addr[5:2]][7:0] <= wr_data[7:0];
                    end
                    REG_TUNING_H: begin
                        tuning_word[wr_addr[5:2]][23:8] <= wr_data[15:0];
                    end
                    REG_COUNTER: begin
                        counter[wr_addr[5:2]] <= wr_data;
                    end
                    REG_COMPARE: begin
                        compare[wr_addr[5:2]] <= wr_data;
                    end
                    REG_MODE: begin
                        mode[wr_addr[5:2]] <= wr_data[7:0];
                    end
                    REG_EV_EN: begin
                        ev_enable[wr_addr[5:2]] <= wr_data[7:0];
                    end
                endcase
            end

            // Timer logic per channel
            for (i = 0; i < NUM_TIMERS; i = i + 1) begin
                // NCO phase accumulator
                phase_acc[i] <= phase_acc[i] + tuning_word[i];

                // NCO clock output (MSB)
                nco_clk_out[i] <= phase_acc[i][23];

                // Mode-specific counter logic
                case (mode[i][3:0])
                    MODE_COUNT_UP: begin
                        counter[i] <= counter[i] + 1;
                        if (counter[i] == 16'hFFFF) begin
                            if (ev_enable[i] & EV_OVERFLOW) begin
                                ev_status[i] <= ev_status[i] | EV_OVERFLOW;
                                timer_event[i] <= 1'b1;
                            end
                        end
                    end
                    MODE_COUNT_DOWN: begin
                        if (counter[i] > 0) counter[i] <= counter[i] - 1;
                        if (counter[i] == 1) begin
                            if (ev_enable[i] & EV_CMP_MATCH) begin
                                ev_status[i] <= ev_status[i] | EV_CMP_MATCH;
                                timer_event[i] <= 1'b1;
                            end
                        end
                    end
                    MODE_NCO_CLK: begin
                        // Counter not used, NCO MSB is clock output
                    end
                    MODE_NCO_VAR: begin
                        // Variable duty: counter vs compare
                        counter[i] <= counter[i] + 1;
                        if (counter[i] >= compare[i]) begin
                            nco_clk_out[i] <= 1'b0;
                        end else begin
                            nco_clk_out[i] <= 1'b1;
                        end
                    end
                    MODE_PWM: begin
                        counter[i] <= counter[i] + 1;
                        nco_clk_out[i] <= (counter[i] < compare[i]);
                    end
                    MODE_CAPTURE: begin
                        counter[i] <= counter[i] + 1;
                        // Pin edge capture
                        if (pin_rise[i] && !pin_prev[i]) begin
                            capture[i] <= counter[i];
                            if (ev_enable[i] & EV_PIN_RISE) begin
                                ev_status[i] <= ev_status[i] | EV_PIN_RISE;
                                timer_event[i] <= 1'b1;
                            end
                        end
                        if (!pin_rise[i] && pin_prev[i]) begin
                            capture[i] <= counter[i];
                            if (ev_enable[i] & EV_PIN_FALL) begin
                                ev_status[i] <= ev_status[i] | EV_PIN_FALL;
                                timer_event[i] <= 1'b1;
                            end
                        end
                        pin_prev[i] <= pin_rise[i];
                    end
                    MODE_MEASURE: begin
                        counter[i] <= counter[i] + 1;
                        // Measure pulse width and period
                        if (pin_rise[i] && !pin_prev[i]) begin
                            capture[i] <= counter[i]; // Period
                            prev_counter[i] <= counter[i];
                            if (ev_enable[i] & EV_PIN_RISE) begin
                                ev_status[i] <= ev_status[i] | EV_PIN_RISE;
                                timer_event[i] <= 1'b1;
                            end
                        end
                        if (!pin_rise[i] && pin_prev[i]) begin
                            capture[i] <= counter[i] - prev_counter[i]; // Pulse width
                            if (ev_enable[i] & EV_PIN_FALL) begin
                                ev_status[i] <= ev_status[i] | EV_PIN_FALL;
                                timer_event[i] <= 1'b1;
                            end
                        end
                        pin_prev[i] <= pin_rise[i];
                    end
                endcase

                // Compare match event
                if (mode[i][3:0] != MODE_OFF && counter[i] == compare[i] && compare[i] != 0) begin
                    if (ev_enable[i] & EV_CMP_MATCH) begin
                        ev_status[i] <= ev_status[i] | EV_CMP_MATCH;
                        timer_event[i] <= 1'b1;
                    end
                end
            end
        end
    end

    // Read handling
    always @(*) begin
        rd_data = 16'h0000;
        case (wr_addr[1:0])
            REG_TUNING:   rd_data = {8'h00, tuning_word[wr_addr[5:2]][7:0]};
            REG_TUNING_H: rd_data = tuning_word[wr_addr[5:2]][23:8];
            REG_COUNTER:  rd_data = counter[wr_addr[5:2]];
            REG_CAPTURE:  rd_data = capture[wr_addr[5:2]];
            REG_COMPARE:  rd_data = compare[wr_addr[5:2]];
            REG_MODE:     rd_data = {8'h00, mode[wr_addr[5:2]]};
            REG_EV_EN:    rd_data = {8'h00, ev_enable[wr_addr[5:2]]};
            REG_EV_ST:    rd_data = {8'h00, ev_status[wr_addr[5:2]]};
            default:      rd_data = 16'h0000;
        endcase
    end

    // Clear event status on read of REG_EV_ST
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // handled above
        end else if (!wr_en && wr_addr[1:0] == REG_EV_ST) begin
            ev_status[wr_addr[5:2]] <= 8'h00;
        end
    end

endmodule
