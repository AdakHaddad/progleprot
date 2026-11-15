# plan.md — Protocol Discovery Core (Tiny Tapeout IHP challenge)

Status: v0.2. Rewritten for the challenge brief.

## Goal
A discovery core that watches unknown serial signals, infers the protocol, and emits a sequencer program that reproduces it. Target: IHP 130nm CMOS5L via Tiny Tapeout, 8x4 tiles (March 2027 shuttle).

## Pitch
"A protocol analyzer and bridge that learns by itself, with no PC." Discovery is the main content of the die. Sequencers are a small supporting block. Not an RP2040 clone.

## Fixed constraints (from brief; re-verify in the template)
- 8x4 tiles = 32 tiles, roughly 1.0 mm² nominal
- Rough budget: ~1K logic cells per tile, so ~32K cells total
- Leave room for clock tree and routing; run synthesis early
- SRAM macro can beat flops for memory
- Check in the template: IO pin count, clock limits, SRAM macro availability

## Scope
**Core:** UART, SPI, I²C
**Next (cheap, same encoding class):** PS/2, JTAG, SWD fingerprints
**Next (needs NRZI + stuffing layer):** CAN, low-speed USB
**Stretch:** 10BASE-T Ethernet (needs oversampling above likely tile clock + external differential receiver)
**Out:** analog/ADC front end, active L* probing (L3), encrypted links

## Headline features
1. Fingerprint-first discovery with ranked guesses and confidence
2. Shared encoding layer (NRZ, NRZI, Manchester, bit-stuffing)
3. **Pin-role discovery:** auto-assign clock/data/CS/TX/RX across the input pins
4. Compile result into a sequencer program and replay it (closed loop)
5. Glitch/jitter/drift flags from the histogram data

## Decisions made
- No CPU. FSMs + ROM only (area budget forces this)
- Fingerprint library in ROM; blind inference kept small
- Histograms: log-spaced buckets, narrow saturating counters
- Passive by default; no active probing in v1

## Milestones
| # | Milestone | Where |
|---|---|---|
| M0 | Template builds end to end (RTL -> GDS) with a trivial block; record area and timing | TT flow |
| M1 | edge_interval + log histogram + peak detector | sim + Basys3 |
| M2 | UART auto-baud + framing | sim + Basys3 |
| M3 | SPI and I²C detection (clock/data roles, mode, address frames) | sim + Basys3 |
| M4 | Fingerprint ROM + ranked output | sim + Basys3 |
| M5 | Pin-role discovery | sim + Basys3 |
| M6 | Sequencer + compile + replay (closed loop) | sim + Basys3 |
| M7 | Synthesis area check on the full design; prune to fit | TT flow |
| M8 | Encoding layer: PS/2, then NRZI/stuffing (CAN, USB LS) | sim + Basys3 |
| M9 | Full P&R, timing closure, final verification pass | TT flow |
| M10 | Stretch: 10BASE-T if time and clock allow | sim |

Run synthesis at every milestone, not just M7. Track cell count per block in architecture.md.

## Risks
- Area overrun: mitigated by per-block budgets and early synthesis
- Clock limits may cap supported rates: check before promising rates
- Hardcaml learning curve: prototype one block in both Hardcaml and Verilog first
- Scope creep: protocols beyond the core list only after M7 fits

## Open questions
- Exact Tiny Tapeout IHP IO count, clock range, SRAM macro availability
- Hardcaml vs Verilog as the source of truth
- Host interface: how results and the sequencer program leave the chip
- How much of the fingerprint library fits in ROM
