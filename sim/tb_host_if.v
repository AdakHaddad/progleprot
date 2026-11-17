module tb_host_if;
    reg clk = 0, rst_n = 0;
    reg spi_sck = 1, spi_mosi = 0, spi_cs_n = 1;
    wire spi_miso;
    wire ram_wr_en;
    wire [7:0] ram_wr_addr;
    wire [31:0] ram_wr_data;
    wire seq_start;
    wire [7:0] seq_prog_len;
    wire [1:0] host_state;

    host_if #(
        .ADDR_W(8),
        .DATA_W(32)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .spi_sck(spi_sck), .spi_mosi(spi_mosi), .spi_miso(spi_miso), .spi_cs_n(spi_cs_n),
        .ram_wr_en(ram_wr_en), .ram_wr_addr(ram_wr_addr), .ram_wr_data(ram_wr_data),
        .seq_start(seq_start), .seq_prog_len(seq_prog_len), .host_state(host_state)
    );

    always #10 clk = ~clk;  // 50MHz (20ns period in default time units)

    integer b;
    reg [63:0] cmd_word;

    task wait_clk(input integer n);
        integer j;
        begin for (j = 0; j < n; j = j + 1) @(negedge clk); end
    endtask

    task wait_idle;
        begin
            $display("t=%0t wait_idle: checking dut.st=%d", $time, dut.st);
            while (dut.st != 0) begin
                @(posedge clk);
                $display("t=%0t wait_idle: dut.st=%d", $time, dut.st);
            end
            $display("t=%0t wait_idle: dut is IDLE", $time);
        end
    endtask

    // Build 64-bit SPI command: data(32) | addr(16) | cmd(8) | pad(8)
    // Sent MSB first, so first byte = data[31:24], last byte = pad[7:0]
    function [63:0] make_cmd;
        input [31:0] data;
        input [15:0] addr;
        input [7:0]  cmd;
        begin
            make_cmd = {data, addr, cmd, 8'h00};
            $display("make_cmd: data=%h addr=%h cmd=%h -> %h", data, addr, cmd, make_cmd);
        end
    endfunction

    task send_spi_cmd(input [63:0] cmd);
        integer i;
        begin
            $display("t=%0t send_spi_cmd: waiting for idle first", $time);
            wait_idle;
            wait_clk(4);
            
            $display("t=%0t send_spi_cmd: starting SPI transaction", $time);
            spi_cs_n = 0;
            wait_clk(2);
            for (i = 63; i >= 0; i = i - 1) begin
                spi_mosi = cmd[i];
                spi_sck = 0; wait_clk(2);
                spi_sck = 1; wait_clk(2);
            end
            spi_cs_n = 1;
            $display("t=%0t send_spi_cmd: SPI done, waiting for idle", $time);
            wait_idle;
            wait_clk(4);
        end
    endtask

    initial begin
        rst_n = 0;
        wait_clk(4);
        rst_n = 1;
        wait_clk(4);

        $display("=== Host IF SPI Test ===");

        // Send WRITE command: addr=0x05, data=0xDEADBEEF
        $display("Sending WRITE command (addr=5, data=DEADBEEF)...");
        send_spi_cmd(make_cmd(32'hDEADBEEF, 16'h0005, 8'h01));

        $display("After WRITE: ram_wr_en=%b, addr=%h, data=%h, seq_prog_len=%d, state=%d",
                 ram_wr_en, ram_wr_addr, ram_wr_data, seq_prog_len, host_state);

        // Send RUN command: length=6
        $display("Sending RUN command (length=6)...");
        send_spi_cmd(make_cmd(32'h00000006, 16'h0006, 8'h03));

        $display("After RUN: seq_start=%b, seq_prog_len=%d, state=%d",
                 seq_start, seq_prog_len, host_state);

        $display("Test complete");
        $finish;
    end

    // Monitor
    always @(posedge clk) begin
        if (ram_wr_en) $display("t=%0t WRITE: addr=%h data=%h", $time, ram_wr_addr, ram_wr_data);
        if (seq_start) $display("t=%0t SEQ_START pulse", $time);
    end

    initial begin #500000; $display("TIMEOUT"); $finish; end
endmodule
