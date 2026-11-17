module tb_emu_uart;
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
    wire       seq_start = dut.u_sequencer.start;
    wire [7:0] prog_len = dut.u_sequencer.prog_len;
    wire       prog_valid = dut.u_sequencer.prog_valid;
    wire [1:0] seq_st = dut.u_sequencer.st;
    wire       host_seq_start = dut.u_host_if.seq_start;
    wire [7:0] host_prog_len = dut.u_host_if.seq_prog_len;
    wire [1:0] host_st = dut.u_host_if.st;

    task wait_clk(input integer n);
        integer j;
        begin for (j = 0; j < n; j = j + 1) @(negedge clk); end
    endtask

    // Build SPI command: {data(32), addr(16), cmd(8), pad(8)} = 64 bits
    // Sent MSB first
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
            $display("spi_write: addr=%h data=%h (OP=%h mask=%h mode=%h reg=%h) cmd=%h", 
                     addr, data, data[31:28], data[27:24], data[23:22], data[21:20], cmd);
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
            $display("spi_run: length=%h cmd=%h", length, cmd);
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

    // Instruction encoding matching pdis_sequencer:
    // [31:28] = OP (4 bits) - OP_DRIVE=1
    // [27:24] = pin_mask (4 bits)
    // [23:22] = mode (2 bits) - DRV_LOW=0, DRV_HIGH=1, DRV_Z=2, DRV_REG=3
    // [21:20] = reg_idx (2 bits) - for DRV_REG
    // [19:0] = unused (20 bits)
    function [31:0] INS_DRIVE(input [3:0] mask, input [1:0] mode, input [1:0] reg_idx);
        begin INS_DRIVE = {4'd1, mask, mode, reg_idx, 20'd0}; end
    endfunction

    function [31:0] INS_WAIT(input [3:0] wait_mode, input [15:0] count);
        begin INS_WAIT = {4'd2, wait_mode, 12'd0, count}; end
    endfunction

    function [31:0] INS_NOP;
        begin INS_NOP = 32'h00000000; end
    endfunction

    initial begin
        rst_n = 0;
        wait_clk(4);
        rst_n = 1;
        wait_clk(4);

        $display("=== Protocol Emulator UART TX Test ===");

        // Pin 0 high for 10 cycles
        spi_write(8'h00, INS_DRIVE(4'h1, 2'b01, 2'd0));
        spi_write(8'h01, INS_WAIT(4'd0, 16'd10));
        // Pin 0 low for 20 cycles  
        spi_write(8'h02, INS_DRIVE(4'h1, 2'b00, 2'd0));
        spi_write(8'h03, INS_WAIT(4'd0, 16'd20));
        // Pin 0 high for 20 cycles
        spi_write(8'h04, INS_DRIVE(4'h1, 2'b01, 2'd0));
        spi_write(8'h05, INS_WAIT(4'd0, 16'd20));
        // Pin 0 low for 20 cycles
        spi_write(8'h06, INS_DRIVE(4'h1, 2'b00, 2'd0));
        spi_write(8'h07, INS_WAIT(4'd0, 16'd20));
        // Pin 0 high for 20 cycles
        spi_write(8'h08, INS_DRIVE(4'h1, 2'b01, 2'd0));
        spi_write(8'h09, INS_WAIT(4'd0, 16'd20));
        // Pin 0 low for 20 cycles
        spi_write(8'h0A, INS_DRIVE(4'h1, 2'b00, 2'd0));
        spi_write(8'h0B, INS_WAIT(4'd0, 16'd20));
        // Pin 0 high for 20 cycles
        spi_write(8'h0C, INS_DRIVE(4'h1, 2'b01, 2'd0));
        spi_write(8'h0D, INS_WAIT(4'd0, 16'd20));
        // Pin 0 low for 20 cycles
        spi_write(8'h0E, INS_DRIVE(4'h1, 2'b00, 2'd0));
        spi_write(8'h0F, INS_WAIT(4'd0, 16'd20));
        // Pin 0 high for 20 cycles
        spi_write(8'h10, INS_DRIVE(4'h1, 2'b01, 2'd0));
        spi_write(8'h11, INS_WAIT(4'd0, 16'd20));
        // Pin 0 low for 20 cycles
        spi_write(8'h12, INS_DRIVE(4'h1, 2'b00, 2'd0));
        spi_write(8'h13, INS_WAIT(4'd0, 16'd20));
        // Pin 0 high for 20 cycles
        spi_write(8'h14, INS_DRIVE(4'h1, 2'b01, 2'd0));
        spi_write(8'h15, INS_WAIT(4'd0, 16'd20));
        // Pin 0 high (stop bit)
        spi_write(8'h16, INS_DRIVE(4'h1, 2'b01, 2'd0));
        spi_write(8'h17, INS_NOP());

        $display("Program loaded. Starting sequencer...");

        spi_run(8'd24);

        // Monitor for 20 cycles after RUN to catch start pulse
        repeat (20) begin
            @(posedge clk);
            $display("t=%0t host_st=%d host_seq_start=%b host_prog_len=%d | seq_st=%d seq_start=%b prog_len=%d pc=%d done=%b error=%b",
                     $time, host_st, host_seq_start, host_prog_len,
                     seq_st, seq_start, prog_len, seq_pc, seq_done, seq_error);
        end

        // Wait for sequencer to complete
        wait_clk(5000);
        $display("Final: seq_st=%d pc=%d done=%b error=%b", seq_st, seq_pc, seq_done, seq_error);

        $display("Test complete");
        $finish;
    end

    // Monitor pin 0
    always @(posedge clk) begin
        if (pin_oe[0]) begin
            $display("t=%0t PIN0_OUT=%b OE=%b pc=%d seq_st=%d", $time, pin_out[0], pin_oe[0], seq_pc, seq_st);
        end
    end

    initial begin #1000000; $display("TIMEOUT"); $finish; end
endmodule
