module tb_emu_spi_master;
    reg clk = 0, rst_n = 0, ena = 1;
    reg [7:0] ui_in = 0;
    reg [7:0] uio_in = 8'hFF;
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    tt_um_protocol_emu dut (
        .ui_in(ui_in), .uo_out(uo_out), .uio_in(uio_in), .uio_out(uio_out), .uio_oe(uio_oe),
        .ena(ena), .clk(clk), .rst_n(rst_n)
    );

    always #10 clk = ~clk;

    wire [7:0] pin_out = dut.pin_out;
    wire [7:0] pin_oe  = dut.pin_oe;
    wire [7:0] seq_pc  = dut.seq_pc;
    wire       seq_done = dut.seq_done;
    wire       seq_error = dut.seq_error;
    wire [1:0] seq_st = dut.u_sequencer.st;
    wire [15:0] reg0 = dut.u_sequencer.reg_file[0];
    wire [15:0] reg1 = dut.u_sequencer.reg_file[1];
    wire [15:0] reg2 = dut.u_sequencer.reg_file[2];
    wire [15:0] reg3 = dut.u_sequencer.reg_file[3];

    task wait_clk(input integer n);
        integer j;
        begin for (j = 0; j < n; j = j + 1) @(negedge clk); end
    endtask

    function [63:0] make_spi_cmd;
        input [31:0] data;
        input [15:0] addr;
        input [7:0]  cmd;
        begin
            make_spi_cmd = {data, addr, cmd, 8'h00};
        end
    endfunction

    task spi_write(input [15:0] addr, input [31:0] data);
        integer b;
        reg [63:0] cmd;
        begin
            cmd = make_spi_cmd(data, addr, 8'h01);
            uio_in[2] = 0;
            wait_clk(2);
            for (b = 63; b >= 0; b = b - 1) begin
                uio_in[1] = cmd[b];
                uio_in[0] = 0; wait_clk(2);
                uio_in[0] = 1; wait_clk(2);
            end
            uio_in[2] = 1;
            wait_clk(4);
        end
    endtask

    task spi_run(input [15:0] length);
        integer b;
        reg [63:0] cmd;
        begin
            cmd = make_spi_cmd(32'h0, length, 8'h03);
            uio_in[2] = 0;
            wait_clk(2);
            for (b = 63; b >= 0; b = b - 1) begin
                uio_in[1] = cmd[b];
                uio_in[0] = 0; wait_clk(2);
                uio_in[0] = 1; wait_clk(2);
            end
            uio_in[2] = 1;
            wait_clk(10);
        end
    endtask

    // Instruction encoding
    function [31:0] INS_LOAD(input [3:0] dst, input [15:0] val);
        begin INS_LOAD = {4'd9, dst, 8'd0, val}; end
    endfunction

    function [31:0] INS_DRIVE(input [3:0] mask, input [1:0] mode, input [1:0] reg_idx);
        begin INS_DRIVE = {4'd1, mask, mode, reg_idx, 20'd0}; end
    endfunction

    function [31:0] INS_WAIT(input [3:0] wait_mode, input [15:0] count);
        begin INS_WAIT = {4'd2, wait_mode, 12'd0, count}; end
    endfunction

    function [31:0] INS_SAMPLE(input [3:0] dst, input [3:0] mask);
        begin INS_SAMPLE = {4'd3, dst, mask, 20'd0}; end
    endfunction

    function [31:0] INS_BRANCH(input [3:0] cond, input [7:0] target);
        begin INS_BRANCH = {4'd5, cond, 12'd0, target}; end
    endfunction

    // SPI Master pins: Pin 0=SCK, Pin 1=MOSI, Pin 2=CS_N (active low), Pin 3=MISO (input)
    // Mode 0: CPOL=0, CPHA=0 - SCK idle low, sample on rising edge

    initial begin
        rst_n = 0;
        wait_clk(4);
        rst_n = 1;
        wait_clk(4);

        $display("=== Protocol Emulator SPI Master Test ===");

        // Simulated slave MISO input on pin 3 (ui_in[3])
        // We'll drive it from testbench to simulate slave response

        // Program: Send 0xA5 (10100101), receive 1 byte
        // Uses loop with BRANCH for 8 bits
        
        // R0 = bit counter (8)
        spi_write(8'h00, INS_LOAD(4'd0, 16'd8));
        // R1 = TX data (0xA5)
        spi_write(8'h01, INS_LOAD(4'd1, 16'h00A5));
        // R2 = RX data accumulator (0)
        spi_write(8'h02, INS_LOAD(4'd2, 16'h0000));
        // R3 = current bit mask (0x80 for MSB first)
        spi_write(8'h03, INS_LOAD(4'd3, 16'h0080));

        // CS low (Pin 2 = 0)
        spi_write(8'h04, INS_DRIVE(4'h4, 2'b00, 2'd0));
        spi_write(8'h05, INS_WAIT(4'd0, 16'd5));

        // Loop label: PC=6
        // SCK low (Pin 0 = 0) - already low from reset
        spi_write(8'h06, INS_DRIVE(4'h1, 2'b00, 2'd0));
        
        // Setup MOSI (Pin 1) from R1 & R3
        // Check if current bit is set: R1 & R3 != 0
        spi_write(8'h07, INS_DRIVE(4'h2, 2'b11, 2'd1)); // DRV_REG mode - uses R1[3:0]... wait, need different approach
        
        // Better: Pre-load MOSI bit into a register using SHIFT/XOR
        // For simplicity, let's do explicit bit-by-bit without loop
        // We'll just do 3 bits to demonstrate

        // Bit 7 (MSB = 1): MOSI high
        spi_write(8'h07, INS_DRIVE(4'h2, 2'b01, 2'd0)); // MOSI high
        spi_write(8'h08, INS_WAIT(4'd0, 16'd5));
        spi_write(8'h09, INS_DRIVE(4'h1, 2'b01, 2'd0)); // SCK high
        spi_write(8'h0A, INS_WAIT(4'd0, 16'd5));
        spi_write(8'h0B, INS_SAMPLE(4'd2, 4'h8)); // Sample MISO (pin 3) into R2
        spi_write(8'h0C, INS_DRIVE(4'h1, 2'b00, 2'd0)); // SCK low
        spi_write(8'h0D, INS_WAIT(4'd0, 16'd5));

        // Bit 6 (0): MOSI low
        spi_write(8'h0E, INS_DRIVE(4'h2, 2'b00, 2'd0)); // MOSI low
        spi_write(8'h0F, INS_WAIT(4'd0, 16'd5));
        spi_write(8'h10, INS_DRIVE(4'h1, 2'b01, 2'd0)); // SCK high
        spi_write(8'h11, INS_WAIT(4'd0, 16'd5));
        spi_write(8'h12, INS_SAMPLE(4'd2, 4'h8)); // Sample MISO
        spi_write(8'h13, INS_DRIVE(4'h1, 2'b00, 2'd0)); // SCK low
        spi_write(8'h14, INS_WAIT(4'd0, 16'd5));

        // Bit 5 (1): MOSI high
        spi_write(8'h15, INS_DRIVE(4'h2, 2'b01, 2'd0)); // MOSI high
        spi_write(8'h16, INS_WAIT(4'd0, 16'd5));
        spi_write(8'h17, INS_DRIVE(4'h1, 2'b01, 2'd0)); // SCK high
        spi_write(8'h18, INS_WAIT(4'd0, 16'd5));
        spi_write(8'h19, INS_SAMPLE(4'd2, 4'h8)); // Sample MISO
        spi_write(8'h1A, INS_DRIVE(4'h1, 2'b00, 2'd0)); // SCK low
        spi_write(8'h1B, INS_WAIT(4'd0, 16'd5));

        // CS high (end transaction)
        spi_write(8'h1C, INS_DRIVE(4'h4, 2'b01, 2'd0)); // CS high
        spi_write(8'h1D, INS_WAIT(4'd0, 16'd5));

        $display("Program loaded (%d instructions). Starting sequencer...", 30);

        // Simulate slave MISO: send 0x5A back
        // We'll toggle ui_in[3] during SCK high phases
        // For now just keep it high
        ui_in[3] = 1; // MISO high

        spi_run(8'd30);

        wait_clk(200);
        
        $display("=== Results ===");
        $display("Final PC: %d", seq_pc);
        $display("Done: %b, Error: %b", seq_done, seq_error);
        $display("R0 (counter): %h", reg0);
        $display("R1 (TX): %h", reg1);
        $display("R2 (RX): %h", reg2);
        $display("R3 (mask): %h", reg3);

        $display("Test complete");
        $finish;
    end

    // Simulate SPI slave MISO response
    // Drive MISO (ui_in[3]) when SCK is high and CS is low
    always @(posedge clk) begin
        // Pin 2 = CS (active low), Pin 0 = SCK
        if (pin_oe[2] && !pin_out[2] && pin_oe[0] && pin_out[0]) begin
            // SCK high, CS low - slave drives MISO
            // Simulate slave sending 0x5A (01011010) - MSB first
            // This is just a simple toggle for demo
            ui_in[3] <= ~ui_in[3];
        end
    end

    // Monitor
    always @(posedge clk) begin
        if (pin_oe[0] || pin_oe[1] || pin_oe[2]) begin
            $display("t=%0t SCK=%b MOSI=%b CS_N=%b MISO_in=%b pc=%d", 
                     $time, pin_out[0], pin_out[1], pin_out[2], ui_in[3], seq_pc);
        end
    end

    initial begin #100000; $display("TIMEOUT"); $finish; end
endmodule
