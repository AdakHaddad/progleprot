module tb_emu_i2c_master;
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

    // I²C pins: Pin 0 = SDA, Pin 1 = SCL
    // Open-drain emulation: DRV_LOW = drive 0, DRV_Z = release (pull-up)
    
    initial begin
        rst_n = 0;
        wait_clk(4);
        rst_n = 1;
        wait_clk(4);

        $display("=== Protocol Emulator I²C Master Test ===");

        // I²C write to address 0x50 (EEPROM), write 0x00 (register), write 0x42 (data)
        // Using 100kHz timing @ 10MHz = 100 cycles per quarter period

        // Idle: SDA=1, SCL=1 (both released)
        spi_write(8'h00, INS_DRIVE(4'h3, 2'b10, 2'd0)); // SDA=Z, SCL=Z
        spi_write(8'h01, INS_WAIT(4'd0, 16'd100));

        // START: SDA falls while SCL high
        spi_write(8'h02, INS_DRIVE(4'h1, 2'b00, 2'd0)); // SDA=0 (drive low)
        spi_write(8'h03, INS_WAIT(4'd0, 16'd50));
        spi_write(8'h04, INS_DRIVE(4'h2, 2'b00, 2'd0)); // SCL=0
        spi_write(8'h05, INS_WAIT(4'd0, 16'd50));

        // Send 7-bit address + W (0x50 << 1 | 0 = 0xA0)
        // Bit 7 (MSB): 1 -> SDA=Z (release)
        spi_write(8'h06, INS_DRIVE(4'h1, 2'b10, 2'd0)); // SDA=Z
        spi_write(8'h07, INS_WAIT(4'd0, 16'd25));
        spi_write(8'h08, INS_DRIVE(4'h2, 2'b10, 2'd0)); // SCL=Z (high)
        spi_write(8'h09, INS_WAIT(4'd0, 16'd50));
        spi_write(8'h0A, INS_DRIVE(4'h2, 2'b00, 2'd0)); // SCL=0
        spi_write(8'h0B, INS_WAIT(4'd0, 16'd25));

        // Bit 6: 0 -> SDA=0
        spi_write(8'h0C, INS_DRIVE(4'h1, 2'b00, 2'd0)); // SDA=0
        spi_write(8'h0D, INS_WAIT(4'd0, 16'd25));
        spi_write(8'h0E, INS_DRIVE(4'h2, 2'b10, 2'd0)); // SCL=Z
        spi_write(8'h0F, INS_WAIT(4'd0, 16'd50));
        spi_write(8'h10, INS_DRIVE(4'h2, 2'b00, 2'd0)); // SCL=0
        spi_write(8'h11, INS_WAIT(4'd0, 16'd25));

        // Bit 5: 1 -> SDA=Z
        spi_write(8'h12, INS_DRIVE(4'h1, 2'b10, 2'd0)); // SDA=Z
        spi_write(8'h13, INS_WAIT(4'd0, 16'd25));
        spi_write(8'h14, INS_DRIVE(4'h2, 2'b10, 2'd0)); // SCL=Z
        spi_write(8'h15, INS_WAIT(4'd0, 16'd50));
        spi_write(8'h16, INS_DRIVE(4'h2, 2'b00, 2'd0)); // SCL=0
        spi_write(8'h17, INS_WAIT(4'd0, 16'd25));

        // Bit 4: 0 -> SDA=0
        spi_write(8'h18, INS_DRIVE(4'h1, 2'b00, 2'd0)); // SDA=0
        spi_write(8'h19, INS_WAIT(4'd0, 16'd25));
        spi_write(8'h1A, INS_DRIVE(4'h2, 2'b10, 2'd0)); // SCL=Z
        spi_write(8'h1B, INS_WAIT(4'd0, 16'd50));
        spi_write(8'h1C, INS_DRIVE(4'h2, 2'b00, 2'd0)); // SCL=0
        spi_write(8'h1D, INS_WAIT(4'd0, 16'd25));

        // Bit 3: 0 -> SDA=0
        spi_write(8'h1E, INS_DRIVE(4'h1, 2'b00, 2'd0)); // SDA=0
        spi_write(8'h1F, INS_WAIT(4'd0, 16'd25));
        spi_write(8'h20, INS_DRIVE(4'h2, 2'b10, 2'd0)); // SCL=Z
        spi_write(8'h21, INS_WAIT(4'd0, 16'd50));
        spi_write(8'h22, INS_DRIVE(4'h2, 2'b00, 2'd0)); // SCL=0
        spi_write(8'h23, INS_WAIT(4'd0, 16'd25));

        // Bit 2: 0 -> SDA=0
        spi_write(8'h24, INS_DRIVE(4'h1, 2'b00, 2'd0)); // SDA=0
        spi_write(8'h25, INS_WAIT(4'd0, 16'd25));
        spi_write(8'h26, INS_DRIVE(4'h2, 2'b10, 2'd0)); // SCL=Z
        spi_write(8'h27, INS_WAIT(4'd0, 16'd50));
        spi_write(8'h28, INS_DRIVE(4'h2, 2'b00, 2'd0)); // SCL=0
        spi_write(8'h29, INS_WAIT(4'd0, 16'd25));

        // Bit 1: 0 -> SDA=0
        spi_write(8'h2A, INS_DRIVE(4'h1, 2'b00, 2'd0)); // SDA=0
        spi_write(8'h2B, INS_WAIT(4'd0, 16'd25));
        spi_write(8'h2C, INS_DRIVE(4'h2, 2'b10, 2'd0)); // SCL=Z
        spi_write(8'h2D, INS_WAIT(4'd0, 16'd50));
        spi_write(8'h2E, INS_DRIVE(4'h2, 2'b00, 2'd0)); // SCL=0
        spi_write(8'h2F, INS_WAIT(4'd0, 16'd25));

        // Bit 0 (W=0): 0 -> SDA=0
        spi_write(8'h30, INS_DRIVE(4'h1, 2'b00, 2'd0)); // SDA=0
        spi_write(8'h31, INS_WAIT(4'd0, 16'd25));
        spi_write(8'h32, INS_DRIVE(4'h2, 2'b10, 2'd0)); // SCL=Z
        spi_write(8'h33, INS_WAIT(4'd0, 16'd50));
        
        // ACK clock: release SDA, sample ACK
        spi_write(8'h34, INS_DRIVE(4'h1, 2'b10, 2'd0)); // SDA=Z (release for ACK)
        spi_write(8'h35, INS_WAIT(4'd0, 16'd25));
        spi_write(8'h36, INS_SAMPLE(4'd0, 4'h1)); // Sample SDA into R0
        spi_write(8'h37, INS_DRIVE(4'h2, 2'b00, 2'd0)); // SCL=0
        spi_write(8'h38, INS_WAIT(4'd0, 16'd25));

        // Now send register address 0x00 (8 bits, all 0)
        // ... simplified: just do a few bits

        // STOP: SDA rises while SCL high
        spi_write(8'h39, INS_DRIVE(4'h1, 2'b00, 2'd0)); // SDA=0
        spi_write(8'h3A, INS_DRIVE(4'h2, 2'b10, 2'd0)); // SCL=Z
        spi_write(8'h3B, INS_WAIT(4'd0, 16'd50));
        spi_write(8'h3C, INS_DRIVE(4'h1, 2'b10, 2'd0)); // SDA=Z (STOP)
        spi_write(8'h3D, INS_WAIT(4'd0, 16'd50));

        $display("Program loaded (%d instructions). Starting sequencer...", 62);

        // Simulate slave ACK (pull SDA low on ACK clock)
        // We'll do this in the monitor

        spi_run(8'd62);

        wait_clk(200);
        
        $display("=== Results ===");
        $display("Final PC: %d", seq_pc);
        $display("Done: %b, Error: %b", seq_done, seq_error);
        $display("R0 (ACK): %h (expected 0 = ACK received)", reg0);

        $display("Test complete");
        $finish;
    end

    // Simulate I²C slave ACK
    // Pull SDA low (ui_in[0] = 0) during ACK clock when master releases SDA
    always @(posedge clk) begin
        // Pin 0 = SDA, Pin 1 = SCL
        // Master releases SDA (pin_oe[0] = 0) and drives SCL high (pin_oe[1]=1, pin_out[1]=1)
        // That's when we should drive ACK
        if (!pin_oe[0] && pin_oe[1] && pin_out[1] && seq_pc >= 8'h34 && seq_pc <= 8'h36) begin
            ui_in[0] <= 0; // Slave pulls SDA low for ACK
        end else begin
            ui_in[0] <= 1; // Otherwise release (pull-up)
        end
    end

    // Monitor I²C bus
    always @(posedge clk) begin
        if (pin_oe[0] || pin_oe[1]) begin
            $display("t=%0t SDA_oe=%b SDA_out=%b SDA_in=%b SCL_oe=%b SCL_out=%b pc=%d", 
                     $time, pin_oe[0], pin_out[0], ui_in[0], pin_oe[1], pin_out[1], seq_pc);
        end
    end

    initial begin #200000; $display("TIMEOUT"); $finish; end
endmodule
