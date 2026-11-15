# verification.md — Verification Plan

Verification is a scored emphasis in the brief. Plan it as a first-class deliverable.

## Layers
1. **Golden model** (Python or OCaml): generates traces with known ground truth and the expected inference result
2. **Directed tests** per block (edge_interval, histogram, framer, crc_sweep, sequencer)
3. **Constrained-random tests**
   - Randomize: baud, jitter, noise glitches, frame contents, idle gaps, protocol mix
   - Check: inferred protocol is in the ranked top-N; no false confident answers
   - Log seeds so failures replay
4. **Formal properties** (e.g. SymbiYosys on the Verilog output)
   - Outputs are tri-state whenever safety is asserted
   - Sequencer never deadlocks and PC stays in bounds
   - Counters saturate instead of wrapping
   - Handshakes never drop or duplicate events
5. **AI-assisted verification**
   - LLM drafts testbenches and properties
   - **Mutation testing** injects bugs into the RTL to measure whether the tests catch them; report the kill rate
   - Humans review everything the model writes; a test is only trusted once it fails on a known-bad mutant
6. **Hardware-in-the-loop:** same RTL on Basys3 against real devices (UART adapter, SPI flash, I²C sensor, PS/2 keyboard)
7. **Post-synthesis / gate-level:** rerun key tests after synthesis and P&R

## Coverage goals
- Every protocol x every encoding x jitter/noise levels
- Every FSM state and transition
- Boundary cases: min/max baud, single-frame captures, no-signal, two signals at once

## Reporting
Keep a table: block, directed tests, random runs, formal properties proven, mutation kill rate. Update at each milestone.

## Rule
A block is not done until its testbench passes and synthesis area is recorded.

## Status log
| Block | Directed | Random / noise | Formal | Mutation kill rate |
|---|---|---|---|---|
| edge_interval, log_bucket, histogram, peak_detect (M1) | 5 tests + spot checks + monotonic sweep | not yet | not yet | not yet |
| m2_top + uart_framer (M2) | 7 clean cases | 6-seed noise suite, 20-seed stress suite, limits probe | not yet | not yet |

Lessons so far: the noise testbench found five real design flaws that the clean directed tests missed (see architecture.md hardening table). Formal properties and mutation testing are still to do.
