# Protocol Emulator ASIC — Project Plan (Tiny Tapeout IHP)

## Goal
Open-source, standalone protocol emulator ASIC: a tiny CPU + hardware timer/pin engine that runs firmware to implement **any digital protocol** with cycle-accurate timing. Target: IHP 130nm CMOS5L via Tiny Tapeout, 8x4 tiles (March 2027 shuttle).

## Pitch
> "One chip, any protocol." Firmware implements UART, SPI, I2C, CAN, USB-LS, Manchester, or proprietary — with hardware timing precision. Built-in capture buffer for reverse engineering. Fully open RTL + firmware + toolchain.

## Fixed Constraints (TT IHP)
- 8x4 tiles = 32 tiles ≈ 1.0 mm² ≈ 32K cells budget
- 50 MHz system clock (TT default)
- 8 bidirectional pins (ui_in/uo_out) + 8 bidirectional IOs (uio)
- Single clock domain
- SRAM macro available for program memory

## Architecture Overview
```
┌─────────────────────────────────────────────────────────────┐
│  Protocol Emulator Core                                     │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌─────────────────────┐  ┌────────────┐  │
│  │  CPU Core    │  │  Timer/Pin          │  │  Program   │  │
│  │  (16-bit,    │◄─│  Coprocessor (×8)   │◄─│  RAM (4KB) │  │
│  │   RISC-like) │  │  - 24-bit NCO       │  │  + Boot    │  │
│  │  + custom    │  │  - 16-bit counter   │  │  ROM (2KB) │  │
│  │  timing insn │  │  - Event logic      │  └────────────┘  │
│  └──────┬───────┘  │  - Pin matrix 8×8   │                  │
│         │          └──────────┬──────────┘                  │
│         │                     │                             │
│         └──────────┬──────────┘                             │
│                    ▼                                       │
│         ┌─────────────────────┐                            │
│         │  Host Interface     │  ← SPI/I2C/UART load      │
│         │  (firmware upload)  │                            │
│         └─────────────────────┘                            │
└─────────────────────────────────────────────────────────────┘
```

## Milestones

| # | Milestone | Deliverable | Est. Cells |
|---|-----------|-------------|------------|
| M0 | ISA spec, area budget, toolchain | `isa.md`, `area_budget.xlsx`, GCC config | — |
| M1 | Minimal CPU core (fetch/decode/exec) | `cpu_core.v`, tests | 3K |
| M2 | Timer coprocessor (8× NCO + counter + events) | `timer_coproc.v`, tests | 4K |
| M3 | Pin matrix (8×8 crossbar + dir/out/in) | `pin_matrix.v`, tests | 1K |
| M4 | Host interface (SPI slave loader) | `host_if.v`, tests | 1K |
| M5 | Program memory (dual-bank 4KB + boot ROM) | `prog_mem.v`, tests | 2K |
| M6 | **Integration: CPU + Timers + Pins + Host** | `emu_top.v`, simulation | 12K |
| M7 | **Firmware: UART TX/RX @ 3Mbps** | `firmware/uart.s`, sim + HW test | — |
| M8 | **Firmware: SPI Master/Slave @ 25MHz** | `firmware/spi.s`, sim + HW test | — |
| M9 | **Firmware: I2C Master @ 1MHz** | `firmware/i2c.s`, sim + HW test | — |
| M10 | Synthesis/P&R, timing closure, TT submission | GDS, reports | 25K |
| M11 | Stretch: CAN, USB-LS, Manchester, Capture | `firmware/*.s`, HW assist blocks | +3K |

## Area Budget (Target: ≤32K cells)

| Block | Est. Cells | Notes |
|-------|------------|-------|
| CPU Core (16-bit, 4-stage, 16 GPRs) | 3,500 | Small pipeline |
| Timer Coprocessor (8× NCO + counter + events) | 4,500 | 24-bit NCO = ~300 ea |
| Pin Matrix (8×8 crossbar + config regs) | 1,200 |  |
| Host Interface (SPI slave) | 1,000 |  |
| Program RAM (dual-bank 4KB) | 2,000 | SRAM macro preferred |
| Boot ROM (2KB) | 500 |  |
| Capture Buffer (256-entry FIFO) | 1,500 |  |
| Optional HW Assist (Manchester, NRZI, CRC) | 1,000 |  |
| **Subtotal** | **~15,200** |  |
| Clock tree, routing margin (30%) | ~4,500 |  |
| **Total** | **~20K** | **37% margin** |

## CPU ISA (16-bit, RISC-like + Timing Extensions)

| Class | Instructions | Encoding |
|-------|--------------|----------|
| ALU | ADD, SUB, AND, OR, XOR, SLT, SLL, SRL, SRA | R-type |
| Immediate | ADDI, ANDI, ORI, XORI, LUI | I-type |
| Memory | LOAD, STORE (8/16-bit) | I-type |
| Control | BEQ, BNE, BLT, BGE, JAL, JALR, RET | B/J-type |
| **Timing (Custom)** | **OUT pin, rs1** — drive pin from reg | Custom |
| | **WAIT timer, rs1** — stall cycles | Custom |
| | **WAITE timer, rs1** — stall until pin event | Custom |
| | **TIME rd, timer** — read timer/capture | Custom |

Base ISA ≈ RV32E compressed to 16-bit. 4 custom instructions for pin/timer control.

## Firmware Library (Target Sizes)

| Protocol | Firmware | HW Assist Used |
|----------|----------|----------------|
| UART TX/RX | ~300 bytes | NCO baud gen |
| SPI Master | ~400 bytes | NCO clock gen |
| SPI Slave | ~300 bytes | Pin event WAITE |
| I2C Master | ~500 bytes | NCO + WAITE |
| CAN 2.0B | ~1KB | Bit-stuff + CRC |
| USB LS Device | ~1.5KB | NRZI + bit-stuff + CRC |
| Manchester (DALI) | ~400 bytes | Manchester encoder |
| Capture/Analyzer | ~600 bytes | Timer capture + FIFO |

## Toolchain
- **Verilog**: iverilog/Verilator for sim, Yosys for synthesis
- **Firmware**: Custom 16-bit GCC/binutils port (or LLVM)
- **Assembler**: GNU as with custom instruction definitions
- **Debug**: Verilator + custom GDB stub

## Verification Strategy
| Layer | Method |
|-------|--------|
| Unit | Directed tests per block (CPU, timer, pin matrix) |
| Integration | Firmware UART/SPI/I2C loopback in sim |
| Random | Constrained-random pin stimulus + firmware |
| Formal | CPU pipeline properties, timer NCO accuracy |
| HW-in-loop | Basys3: UART ↔ FTDI, SPI ↔ Flash, I2C ↔ Sensor |
| Post-synth | Gate-level sim with SDF |

## Risks & Mitigations
| Risk | Mitigation |
|------|------------|
| CPU too large | Start with 16 GPRs, 2-stage pipeline; profile |
| NCO area | Share phase accumulator across timers if needed |
| Firmware toolchain | Use existing 16-bit GCC backend (e.g., msp430-like) |
| Timing closure at 50MHz | Pipeline timer outputs; 2-cycle pin matrix |
| Scope creep | Firmware protocols are *stretch*; M6-M9 core only |

## Success Criteria (Tapeout Ready)
- [ ] All M1-M6 RTL verified, synthesized ≤25K cells
- [ ] UART firmware runs at 3Mbps in gate-level sim
- [ ] SPI firmware runs at 25MHz in gate-level sim  
- [ ] I2C firmware runs at 1MHz in gate-level sim
- [ ] Dual-bank hot-swap demonstrated in sim
- [ ] Capture buffer logs pin events correctly
- [ ] DRC/LVS clean, timing met at 50MHz
- [ ] GDS exported per TT format

## Next Immediate Steps
1. Write `isa.md` with full instruction encoding
2. Write `area_budget.xlsx` with per-block breakdown
3. Implement `cpu_core.v` (M1) — fetch/decode/execute
4. Implement `timer_coproc.v` (M2) — NCO + counter + events
5. Implement `pin_matrix.v` (M3) — crossbar + config
6. Run synthesis after each block to track area
