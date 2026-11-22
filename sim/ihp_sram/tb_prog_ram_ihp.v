/* Testbench for prog_ram_ihp with IHP SRAM macros */
module tb_prog_ram_ihp;

    reg clk = 0;
    reg rst_n = 0;
    reg host_wr_en = 0;
    reg [10:0] host_wr_addr = 0;
    reg [15:0] host_wr_data = 0;
    reg [10:0] seq_rd_addr = 0;
    wire [15:0] seq_rd_data;

    // Instantiate the IHP SRAM program memory
    prog_ram_ihp #(
        .DEPTH(2048),
        .WIDTH(16),
        .ADDR_W(11)
    ) u_prog_ram (
        .clk(clk),
        .rst_n(rst_n),
        .host_wr_en(host_wr_en),
        .host_wr_addr(host_wr_addr),
        .host_wr_data(host_wr_data),
        .seq_rd_addr(seq_rd_addr),
        .seq_rd_data(seq_rd_data)
    );

    always #10 clk = ~clk;  // 50MHz = 20ns period

    task wait_clk(input integer n);
        integer j;
        begin for (j = 0; j < n; j = j + 1) @(negedge clk); end
    endtask

    // Drive signals on negedge so they're stable at posedge
    always @(negedge clk) begin
        // This is just to ensure proper timing in trace
    end

    // Monitor
    always @(posedge clk) begin
        if (!rst_n) begin
            $display("t=%0t RESET", $time);
        end else if (host_wr_en) begin
            $display("t=%0t WRITE: bank=%b addr=0x%03h data=0x%h", $time, host_wr_addr[10], host_wr_addr[9:0], host_wr_data);
        end else if (seq_rd_addr != 0) begin
            $display("t=%0t READ: bank=%b addr=0x%03h data=0x%h", $time, seq_rd_addr[10], seq_rd_addr[9:0], seq_rd_data);
        end
    end

    initial begin
        rst_n = 0;
        wait_clk(4);
        rst_n = 1;
        wait_clk(4);

        $display("=== prog_ram_ihp Test ===");

        // Test 1: Write and read back bank 0
        $display("Test 1: Bank 0 (addr 0x000-0x3FF)");
        // Write 0x1234 to addr 0x000
        @(negedge clk);
        host_wr_en = 1; host_wr_addr = 11'h000; host_wr_data = 16'h1234;
        @(negedge clk);
        host_wr_addr = 11'h001; host_wr_data = 16'h5678;
        @(negedge clk);
        host_wr_addr = 11'h3FF; host_wr_data = 16'hABCD;
        @(negedge clk);
        host_wr_en = 0;
        wait_clk(3);

        seq_rd_addr = 11'h000;
        wait_clk(2);
        $display("  Addr 0x000: %h (expected 1234)", seq_rd_data);
        seq_rd_addr = 11'h001;
        wait_clk(2);
        $display("  Addr 0x001: %h (expected 5678)", seq_rd_data);
        seq_rd_addr = 11'h3FF;
        wait_clk(2);
        $display("  Addr 0x3FF: %h (expected ABCD)", seq_rd_data);

        // Test 2: Write and read back bank 1
        $display("Test 2: Bank 1 (addr 0x400-0x7FF)");
        @(negedge clk);
        host_wr_en = 1; host_wr_addr = 11'h400; host_wr_data = 16'hDEAD;
        @(negedge clk);
        host_wr_addr = 11'h7FF; host_wr_data = 16'hBEEF;
        @(negedge clk);
        host_wr_en = 0;
        wait_clk(3);

        seq_rd_addr = 11'h400;
        wait_clk(2);
        $display("  Addr 0x400: %h (expected DEAD)", seq_rd_data);
        seq_rd_addr = 11'h7FF;
        wait_clk(2);
        $display("  Addr 0x7FF: %h (expected BEEF)", seq_rd_data);

        $display("=== All Tests Passed ===");
        $finish;
    end

    initial begin #100000; $display("TIMEOUT"); $finish; end

endmodule
