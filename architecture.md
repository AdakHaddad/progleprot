# Protocol Emulator ASIC — Architecture Specification

## Overview
A reprogrammable timing engine: tiny 16-bit CPU + 8 hardware timer/counter channels with NCO frequency synthesis, event system, and 8×8 pin crossbar. Firmware implements protocols; hardware guarantees cycle-accurate timing.

## Block Diagram
```
                    ┌─────────────────────────────────────┐
                    │         System Bus (16-bit)         │
                    └──────────────┬──────────────────────┘
                                   │
        ┌──────────────────────────┼──────────────────────────┐
        │                          │                          │
        ▼                          ▼                          ▼
┌───────────────┐        ┌─────────────────┐        ┌────────────────┐
│   CPU Core    │        │ Timer Coproc ×8 │        │  Pin Matrix    │
│  (16-bit)     │        │  - 24-bit NCO   │◄───────│  (8×8 crossbar)│
│  - 16 GPRs    │        │  - 16-bit Cnt   │        │  - DIR/OUT/IN  │
│  - 4-stage    │        │  - Events       │        │  - Sel: CPU/Tmr│
│  - Custom insn│        └────────┬────────┘        └───────┬────────┘
└───────┬───────┘                 │                        │
        │                         │                        │
        ▼                         ▼                        ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Program Memory (Dual-Bank 4KB)                   │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                 │
│  │ Bank A      │  │ Bank B      │  │ Boot ROM    │  ← Atomic swap  │
│  │ (active)    │  │ (staging)   │  │ (2KB)       │     on CMD_SWAP │
│  └─────────────┘  └─────────────┘  └─────────────┘                 │
└─────────────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Host Interface (SPI Slave)                       │
│  - Load firmware to staging bank                                     │
│  - CMD_VERIFY, CMD_SWAP, CMD_ROLLBACK                                │
│  - Status: running, error, version                                   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 1. CPU Core (`cpu_core.v`)

### ISA Summary (16-bit instructions)

| Opcode[15:12] | Mnemonic | Operands | Description |
|--------------|----------|----------|-------------|
| 0x0 | ADD | rd, rs1, rs2 | rd = rs1 + rs2 |
| 0x1 | SUB | rd, rs1, rs2 | rd = rs1 - rs2 |
| 0x2 | AND | rd, rs1, rs2 | rd = rs1 & rs2 |
| 0x3 | OR | rd, rs1, rs2 | rd = rs1 \| rs2 |
| 0x4 | XOR | rd, rs1, rs2 | rd = rs1 ^ rs2 |
| 0x5 | SLT | rd, rs1, rs2 | rd = (rs1 < rs2) ? 1 : 0 (signed) |
| 0x6 | SLL | rd, rs1, rs2 | rd = rs1 << rs2[3:0] |
| 0x7 | SRL | rd, rs1, rs2 | rd = rs1 >> rs2[3:0] |
| 0x8 | ADDI | rd, rs1, imm8 | rd = rs1 + sign_ext(imm8) |
| 0x9 | ANDI | rd, rs1, imm8 | rd = rs1 & imm8 |
| 0xA | ORI | rd, rs1, imm8 | rd = rs1 \| imm8 |
| 0xB | LUI | rd, imm12 | rd = imm12 << 4 |
| 0xC | LOAD | rd, rs1, offset4 | rd = mem[rs1 + offset4] (8/16-bit) |
| 0xD | STORE | rs1, rs2, offset4 | mem[rs1 + offset4] = rs2 |
| 0xE | BRANCH | cond, rs1, rs2, off8 | PC += off8 if cond(rs1,rs2) |
| 0xF | **CUSTOM** | — | Timing extensions (see below) |

### Custom Timing Instructions (Opcode 0xF)

| Funct[3:0] | Mnemonic | Operands | Description |
|-----------|----------|----------|-------------|
| 0x0 | OUT | pin, rs1 | pin_out[pin] = rs1[0]; pin_oe[pin] = 1 |
| 0x1 | DIR | pin, rs1 | pin_dir[pin] = rs1[0] (1=out, 0=in) |
| 0x2 | WAIT | timer, rs1 | Stall CPU for rs1 cycles (timer counts down) |
| 0x3 | WAITE | timer, rs1 | Stall until pin event (rs1 = event mask) |
| 0x4 | TIME | rd, timer | rd = timer_value (counter or capture) |
| 0x5 | TCFG | timer, rs1, rs2 | Configure timer (rs1=mode, rs2=tuning) |
| 0x6 | PINSEL | pin, rs1 | Select pin source: 0=CPU, 1=Timer0..7 |
| 0x7 | EVEN | timer, rs1 | Enable events: rs1[0]=rise, [1]=fall, [2]=capture |
| 0x8 | SWAP | — | Atomic bank swap (staging → active) |
| 0x9 | VERIFY | rd | rd = CRC32 of staging bank |
| 0xA | CAPRD | rd, timer | Read capture FIFO |
| 0xB-F | Reserved | — | Future: DMA, interrupt |

### Pipeline (4-Stage)
```
IF (Fetch) → ID (Decode/RegRead) → EX (ALU/Addr) → WB (Writeback)
   │                                           │
   └────────── Branch resolved in ID ──────────┘
```
- Branch in ID: 1-cycle penalty on taken
- LOAD/STORE: 1-cycle memory access (single-port RAM)
- Custom instructions: EX stage drives pin/timer interfaces

### Registers
- 16 × 16-bit GPRs (x0-x15), x0 hardwired to 0
- PC (16-bit), SP (x1 = stack pointer by convention)
- No CSRs — timer/pin config via custom instructions

---

## 2. Timer Coprocessor (`timer_coproc.v`) ×8

### Per-Timer Resources
| Resource | Width | Function |
|----------|-------|----------|
| Phase Accumulator (NCO) | 24-bit | Frequency synthesis |
| Tuning Word | 24-bit | freq = (tuning × clk) / 2^24 |
| Counter | 16-bit | Cycle counting, pulse width |
| Capture Register | 16-bit | Timestamp on pin event |
| Compare Register | 16-bit | Match → event/interrupt |
| Mode Register | 8-bit | See below |

### Timer Modes (TCFG)
| Mode[3:0] | Name | Behavior |
|----------|------|----------|
| 0x0 | OFF | Timer disabled |
| 0x1 | COUNT_UP | Increment every cycle |
| 0x2 | COUNT_DOWN | Decrement; event at 0 |
| 0x3 | NCO_CLOCK | Output NCO MSB as clock (50% duty) |
| 0x4 | NCO_VAR | Output NCO comparator (variable duty) |
| 0x5 | PWM | Counter + compare → PWM out |
| 0x6 | CAPTURE | Pin event → latch counter to capture reg |
| 0x7 | MEASURE | Rise→Fall width, Fall→Rise period |

### Event System (Per Timer)
| Event | Trigger | Action |
|-------|---------|--------|
| Compare Match | counter == compare | Flag, optional WAITE wake |
| Overflow | counter wraps | Flag |
| Pin Rise | pin rising edge | Capture counter, flag |
| Pin Fall | pin falling edge | Capture counter, flag |
| Pin Both | either edge | Capture counter, flag |
| NCO Toggle | NCO MSB toggles | Clock out |

### NCO Frequency Formula
```
f_out = (tuning_word × f_clk) / 2^24
```
Examples @ 50MHz:
- 115200 baud: tuning = 3,869,888 (0x3B01B0) → exact
- 3,000,000 baud: tuning = 100,663,296 (0x6000000) → exact
- 25 MHz SPI: tuning = 201,326,592 (0xC000000) → exact

### CPU Interface (Memory-Mapped)
| Address | Register | Access |
|---------|----------|--------|
| 0xF000 + t×16 + 0 | TUNING_WORD | RW |
| 0xF000 + t×16 + 2 | COUNTER | R |
| 0xF000 + t×16 + 4 | CAPTURE | R |
| 0xF000 + t×16 + 6 | COMPARE | RW |
| 0xF000 + t×16 + 8 | MODE | RW |
| 0xF000 + t×16 + 10 | EVENT_EN | RW |
| 0xF000 + t×16 + 12 | EVENT_STATUS | R (clear on read) |

---

## 3. Pin Matrix (`pin_matrix.v`)

### Architecture
```
CPU OUT/DIR ──────────┐
                      ├──► [8×8 Crossbar] ───► Pin PAD (bidirectional)
Timer 0..7 OUT ───────┘       │
                              ▼
                      Pin Config (per pin):
                      - DIR: 0=in, 1=out
                      - SEL: 0=CPU, 1=Timer0, ... 8=Timer7
                      - PULL: 0=none, 1=up, 2=down
```

### Pin Config Registers (Memory-Mapped)
| Address | Register | Bits |
|---------|----------|------|
| 0xF100 | PIN_DIR | [7:0] = 1:out, 0:in |
| 0xF102 | PIN_SEL | [3:0] per pin (4 bits × 8 = 32 bits) |
| 0xF106 | PIN_PULL | [1:0] per pin (2 bits × 8 = 16 bits) |
| 0xF108 | PIN_OUT (CPU) | [7:0] — CPU drives when SEL=0 |
| 0xF10A | PIN_IN | [7:0] — read pin state |

---

## 4. Program Memory (`prog_mem.v`)

### Dual-Bank Organization
| Bank | Size | Purpose |
|------|------|---------|
| Bank A (Active) | 4KB (2K × 16-bit) | Currently executing |
| Bank B (Staging) | 4KB | Firmware loading target |
| Boot ROM | 2KB | Golden firmware, loads Bank A on reset |

### Bank Swap Protocol
```
1. Host loads firmware to Bank B via SPI
2. Host sends CMD_VERIFY → returns CRC32
3. Host sends CMD_SWAP → atomic: Bank B → Active, Bank A → Staging
4. CPU fetches from new active bank (PC=0)
5. On fault: watchdog → CMD_ROLLBACK → Bank A → Active
```

### Memory Map
| Range | Mapping |
|-------|---------|
| 0x0000-0x0FFF | Active Program Bank (4KB) |
| 0x1000-0x17FF | Boot ROM (2KB) |
| 0xF000-0xFFFF | Peripheral registers (timer, pin, host) |

---

## 5. Host Interface (`host_if.v`)

### SPI Slave Protocol (Mode 0, MSB First)
```
CS_N ──────────────────────────────────►│
SCK  ────\__/──\__/──\__/── ... ────────►│ (sample on rising)
MOSI ────[CMD][ADDR][DATA]──────────────►│
MISO ◄──────────[STATUS/READBACK]────────┘
```

### Command Format (32-bit words)
| CMD | Format | Description |
|-----|--------|-------------|
| 0x01 | WRITE addr data | Write 16-bit data to addr |
| 0x02 | READ addr | Read 16-bit from addr |
| 0x03 | VERIFY | Return CRC32 of staging bank |
| 0x04 | SWAP | Atomic bank swap |
| 0x05 | RUN | Release CPU from reset (PC=0) |
| 0x06 | RESET | Hold CPU in reset |
| 0x07 | STATUS | Return {running, error, version} |

### SPI Frame
```
Host → Device: [CMD(8)][ADDR(16)][DATA(16)] = 40 bits
Device → Host: [STATUS(8)][DATA(16)] = 24 bits (for READ/VERIFY/STATUS)
```

---

## 6. Capture Buffer (`capture_buf.v`)

### Structure
- 256-entry FIFO
- Each entry: 48 bits = {timestamp[23:0], pins[7:0], event[7:0], timer_id[3:0], reserved[10:0]}

### Event Encoding
| Event[7:0] | Meaning |
|------------|---------|
| 0x01 | Timer compare match |
| 0x02 | Timer overflow |
| 0x04 | Pin rise (any monitored) |
| 0x08 | Pin fall |
| 0x10 | NCO toggle |
| 0x20 | CPU OUT instruction |
| 0x40 | CPU WAITE wake |
| 0x80 | Error/fault |

### Readout
- Host reads via SPI: CMD_CAPTURE_READ → returns FIFO entries
- Auto-stops on full (configurable)

---

## 7. Optional HW Assist Blocks (Area-Permitting)

### Manchester Encoder/Decoder (`manchester.v`)
- Input: NRZ data + clock enable
- Output: Manchester encoded (high→low = 0, low→high = 1)
- Decoder: recovers clock + data from Manchester stream
- ~300 cells

### NRZI Encoder/Decoder + Bit-Stuff (`nrzi_stuff.v`)
- NRZI: 0=transition, 1=no transition
- Bit stuff: after 5/6 consecutive 1s, insert 0
- CRC5/CRC16 calculator integrated
- ~500 cells

### CRC Calculator (`crc_hw.v`)
- Polynomials: CRC5-USB, CRC8, CRC16-CCITT, CRC16-IBM, CRC32
- Streaming: data in → CRC out per byte
- ~200 cells

---

## 8. Clock & Reset

### Clock
- Single 50 MHz domain (TT default)
- All logic synchronous
- NCOs generate protocol clocks internally

### Reset
- Global async active-low (rst_n from TT)
- CPU held in reset until host sends CMD_RUN
- Watchdog: 2^24 cycles without CMD_RUN → auto-reset

---

## 9. Memory Map Summary

| Range | Device | Description |
|-------|--------|-------------|
| 0x0000-0x0FFF | Prog RAM | Active firmware (4KB) |
| 0x1000-0x17FF | Boot ROM | Golden firmware (2KB) |
| 0xF000-0xF07F | Timer 0-7 | 8 timers × 16 bytes |
| 0xF100-0xF10F | Pin Matrix | Config + I/O |
| 0xF200-0xF207 | Host IF | SPI status/control |
| 0xF300-0xF303 | Capture | FIFO read + status |
| 0xF800-0xF803 | HW Assist | Manchester/NRZI/CRC |

---

## 10. Firmware Development Flow

```
firmware/uart.s
       │
       ▼
as/ld (custom 16-bit target)
       │
       ▼
uart.bin (raw 16-bit words)
       │
       ▼
Host PC: python spi_loader.py uart.bin
       │
       ▼
SPI → staging bank → VERIFY → SWAP → RUN
       │
       ▼
Chip executes UART firmware @ 3Mbps
```

---

## Area Estimate Details (Post-Synthesis Targets)

| Block | Target Cells | Notes |
|-------|--------------|-------|
| CPU Core | 3,500 | 4-stage, 16 GPRs, custom insn |
| Timer ×8 | 4,500 | NCO + counter + events |
| Pin Matrix | 1,200 | 8×8 crossbar + config |
| Host IF | 1,000 | SPI slave |
| Prog RAM (dual 4KB) | 2,000 | SRAM macro preferred |
| Boot ROM | 500 | |
| Capture Buffer | 1,500 | 256×48 FIFO |
| HW Assist | 1,000 | Manchester + NRZI + CRC |
| **Subtotal** | **15,200** | |
| Clock/Route (30%) | 4,500 | |
| **Total** | **~20K** | **< 32K budget** |

---

## Next Steps
1. Write `isa.md` with full instruction encoding tables
2. Implement `cpu_core.v` (M1)
3. Implement `timer_coproc.v` (M2) 
4. Implement `pin_matrix.v` (M3)
5. Run synthesis after each to track area
