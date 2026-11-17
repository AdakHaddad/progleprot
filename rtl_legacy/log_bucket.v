// log_bucket: maps an interval to a log-spaced bucket index.
// 2^FRAC buckets per octave. Index = msb*2^FRAC + the FRAC bits below the msb.
// Default W=16, FRAC=2 -> 64 buckets (~19% resolution). x==0 maps to bucket 0.
module log_bucket #(
    parameter W    = 16,
    parameter FRAC = 2
) (
    input  wire [W-1:0]                       x,
    output reg  [$clog2(W)+FRAC-1:0]          idx
);
    integer i;
    integer msb;
    reg [W-1:0] shifted;
    always @* begin
        msb = 0;
        for (i = 0; i < W; i = i + 1)
            if (x[i]) msb = i;
        if (msb >= FRAC) shifted = x >> (msb - FRAC);
        else             shifted = x << (FRAC - msb);
        idx = (msb << FRAC) | (shifted & ((1 << FRAC) - 1));
    end
endmodule
