`timescale 1ns/1ps
module tb_m2;
    reg clk = 0, rst_n = 0, sig = 1;
    wire done, fail, data8;
    wire [15:0] bit_cycles;
    wire [1:0] parity;
    wire [2:0] phase;
    wire [7:0] n_frames;
    integer errors = 0;

    m2_top dut (.clk(clk), .rst_n(rst_n), .signal_in(sig), .done(done), .fail(fail),
                .bit_cycles(bit_cycles), .data8(data8), .parity(parity),
                .phase(phase), .n_frames(n_frames));
    always #5 clk = ~clk;

    task wait_clk(input integer n);
        integer j; begin for (j = 0; j < n; j = j + 1) @(negedge clk); end
    endtask

    // par: 0 none, 1 even, 2 odd. nbits: 7 or 8. 1 stop bit. 13 bit-times idle gap after.
    task send_frame(input [7:0] d, input integer nbits, input integer par, input integer cpb);
        integer bi; reg p;
        begin
            p = ^(d & ((1 << nbits) - 1));
            sig = 0; wait_clk(cpb);
            for (bi = 0; bi < nbits; bi = bi + 1) begin sig = d[bi]; wait_clk(cpb); end
            if (par == 1) begin sig = p;  wait_clk(cpb); end
            if (par == 2) begin sig = ~p; wait_clk(cpb); end
            sig = 1; wait_clk(cpb);
            wait_clk(13 * cpb);
        end
    endtask

    integer nsent;
    task run_case(input integer nbits, input integer par, input integer cpb, input integer ascii,
                  input integer exp_data8, input integer exp_par);
        reg [7:0] d;
        begin
            rst_n = 0; sig = 1; wait_clk(5); rst_n = 1; wait_clk(20);
            nsent = 0;
            while (!done && nsent < 400) begin
                d = $random;
                if (ascii) d = d & 8'h7F;
                send_frame(d, nbits, par, cpb);
                nsent = nsent + 1;
            end
            if (!done || fail || bit_cycles !== cpb || data8 !== exp_data8[0] || parity !== exp_par[1:0]) begin
                $display("FAIL %0dbit par=%0d cpb=%0d: done=%0d fail=%0d T=%0d data8=%0d parity=%0d",
                         nbits, par, cpb, done, fail, bit_cycles, data8, parity);
                errors = errors + 1;
            end else
                $display("PASS %0d data bits, parity=%0d, T=%0d cycles (frames sent %0d)",
                         nbits, par, bit_cycles, nsent);
        end
    endtask

    initial begin
        run_case(8, 0, 100, 0, 1, 0);   // 8N1 random bytes
        run_case(8, 0, 100, 1, 1, 0);   // 8N1 ASCII (bit7 = 0)
        run_case(8, 1,  87, 0, 1, 1);   // 8E1 at a different baud
        run_case(8, 2,  64, 0, 1, 2);   // 8O1
        run_case(7, 0,  50, 0, 0, 0);   // 7N1
        run_case(7, 1,  80, 0, 0, 1);   // 7E1
        run_case(7, 2, 120, 0, 0, 2);   // 7O1
        if (errors == 0) $display("ALL TESTS PASSED"); else $display("%0d TEST(S) FAILED", errors);
        $finish;
    end
    initial begin #2000000000; $display("TIMEOUT"); $finish; end
endmodule
