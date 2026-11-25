# How It Works — Deep Dive: Protocol Emulator Architecture

## The Big Picture

The Protocol Emulator is a **reprogrammable timing engine** — not a fixed-protocol ASIC. It consists of a tiny CPU with custom timing instructions, hardware timer/counters with NCO frequency synthesis, and a programmable pin crossbar. The protocol behavior lives entirely in firmware.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         PROTOCOL EMULATOR CHIP                               │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                         HOST INTERFACE (SPI)                         │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐            │   │
│  │  │  SPI     │  │  CMD     │  │  ADDR    │  │  DATA    │            │   │
│  │  │  Slave   │──►│  Decode  │──►│  Decode  │──►│  Write   │            │   │
│  │  └──────────┘  └──────────┘  └──────────┘  └────┬─────┘            │   │
│  └──────────────────────────────────────────────────│──────────────────┘   │
│                                                     │                      │
│                    ┌────────────────────────────────┼──────────────────┐   │
│                    │        PROGRAM MEMORY          │                  │   │
│                    │  ┌─────────────────────────┐   │                  │   │
│                    │  │   4 KB (2048 × 16-bit)  │◄──┘                  │   │
│                    │  │   ┌─────────────────┐   │                      │   │
│                    │  │   │  YOUR FIRMWARE  │   │                      │   │
│                    │  │   └─────────────────┘   │                      │   │
│                    │  └──────────────┬──────────┘                      │   │
│                    └───────────────────│──────────────────────────────┘   │
│                                        │                                  │
│                    ┌───────────────────┼──────────────────────────────┐   │
│                    │       CPU CORE (16-bit, 4-stage pipeline)        │   │
│                    │  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐                │   │
│                    │  │ IF  │►│ ID  │►│ EX  │►│ WB  │                │   │
│                    │  └─────┘ └─────┘ └─────┘ └─────┘                │   │
│                    │       │      │      │      │                    │   │
│                    │       ▼      ▼      ▼      ▼                    │   │
│                    │  ┌─────────────────────────────────────┐       │   │
│                    │  │        REGISTER FILE (×16)          │       │   │
│                    │  │  r0=zero  r1-r13=GP  r14=LR  r15=SP │       │   │
│                    │  └─────────────────────────────────────┘       │   │
│                    └───────────────────┬────────────────────────────┘   │
│                                        │                                 │
│        ┌───────────────────────────────┼───────────────────────────┐    │
│        │                               │                               │    │
│        ▼                               ▼                               ▼    │
│ ┌─────────────┐              ┌─────────────────┐            ┌─────────────┐ │
│ │   TIMER     │              │   PIN MATRIX    │            │   HOST IF   │ │
│ │ COPROCESSOR │              │   (8×8 CROSSBAR)│            │  (STATUS)   │ │
│ │             │              │                 │            │             │ │
│ │ 8 Timers    │              │ Per Pin:        │            │ CPU running │ │
│ │ Each:       │              │ • Source (CPU/  │            │ CPU error   │ │
│ │ • 24-bit NCO│              │   Timer0-7)     │            │ Host state  │ │
│ │ • 16-bit Ctr│              │ • Direction     │            │ CRC/verify  │ │
│ │ • Capture   │              │ • Pull up/down  │            └─────────────┘ │
│ │ • Compare   │              │ • Output Enable │                    ▲       │
│ │ • PWM       │              │                 │                    │       │
│ │ • Events    │              │ Pin In ────────►│ Synchronizer     │       │
│ └──────┬──────┘              └────────┬────────┘                    │       │
│        │                              │                              │       │
│        │ Timer NCO/PWM/Events         │ Pin Out/OE                    │       │
│        │                              │                              │       │
│        ▼                              ▼                              │       │
│ ┌─────────────────────────────────────────────────────────────────────┐   │
│ │                        8 EXTERNAL PINS                               │   │
│ │  ui_in[7:0] ──────────► Inputs                                        │   │
│ │  uo_out[7:0] ◄──────── Outputs                                        │   │
│ │  uio_oe[7:0] ◄──────── Output Enables                                │   │
│ └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Core Philosophy: Firmware-Defined Protocols

**Traditional ASIC Approach:**
```
Fixed UART Block ──► Fixed SPI Block ──► Fixed I²C Block
      │                  │                   │
      ▼                  ▼                   ▼
  Registers          Registers           Registers
  (configure)        (configure)         (configure)
```

**This Project's Approach:**
```
┌────────────────────────────────────────────────────────────┐
│                    ONE REPROGRAMMABLE CORE                  │
│                                                             │
│  CPU executes YOUR firmware:                               │
│  • UART TX?  → Write UART bit-bang loop                    │
│  • SPI Master? → Write SPI state machine                   │
│  • I²C Slave?  → Write I²C open-drain emulator             │
│  • Custom?     → Write whatever you need                   │
│                                                             │
│  Hardware provides:                                        │
│  • Cycle-accurate timing (WAIT/WAITE)                      │
│  • Hardware clocks (Timer NCO)                             │
│  • Pin routing (CPU ↔ Timer)                               │
│  • Edge detection (Timer capture)                          │
└────────────────────────────────────────────────────────────┘
```

---

## 1. CPU Core (`cpu_core.v`)

### Architecture
- **16-bit RISC-like** with 4-stage pipeline (IF→ID→EX→WB)
- **16 general-purpose registers** (x0-x15, x0 hardwired to 0)
- **Custom timing instructions** in opcode 0xF space
- **Memory-mapped I/O** for all peripherals (no LOAD/STORE instructions)

### Pipeline Stages

| Stage | Function |
|-------|----------|
| **IF** (Instruction Fetch) | Fetch 16-bit instruction from program memory using PC (byte address) |
| **ID** (Instruction Decode) | Decode opcode, read register file with forwarding, evaluate branches, compute ALU results |
| **EX** (Execute) | Handle peripheral writes, decrement WAIT counters, pass through ALU results |
| **WB** (Writeback) | Write register file, handle custom instruction results (TIME, CAPRD, etc.) |

### ISA Summary (16-bit instructions)

| Opcode[15:12] | Type | Format | Description |
|--------------|------|--------|-------------|
| 0x0 | ALU | rd, rs1, rs2 | ALU ops (ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT) |
| 0x8-0xF | IMM | rd, imm8 | Immediate ops (ADDI, SUBI, ANDI, ORI, XORI, SHLI, SHRI, SRAI) |
| 0xA | BEQZ | rs1, offset8 | Branch if rs1 == 0 |
| 0xB | BNEZ | rs1, offset8 | Branch if rs1 != 0 |
| 0xC | BLTZ | rs1, offset8 | Branch if rs1 < 0 (signed) |
| 0xD | BGEZ | rs1, offset8 | Branch if rs1 >= 0 (signed) |
| 0xE | JAL | rd, offset8 | Jump and Link (rd = PC+2, PC += offset) |
| 0xF | CUSTOM | funct, rs1, rs2/rd | Timing/peripheral instructions |

### Custom Timing Instructions (Opcode 0xF)

| Funct[11:8] | Mnemonic | Operands | Description |
|------------|----------|----------|-------------|
| 0x0 | OUT | pin, val | Drive pin_out[pin] = val[0], pin_oe[pin] = 1 |
| 0x1 | DIR | pin, dir | Set pin_dir[pin] = dir[0] (1=out, 0=in) |
| 0x2 | WAIT | timer, cycles | Stall CPU for `cycles` cycles using timer counter |
| 0x3 | WAITE | timer, event | Stall until timer event (bitmask: 1=rise, 2=fall, 4=capture) |
| 0x4 | TIME | rd, timer | rd = timer counter value |
| 0x5 | TCFG | timer, config | Configure timer mode (see timer modes below) |
| 0x6 | TUNING | timer, value | Set timer NCO tuning (24-bit across low/mid/high) |
| 0x7 | PINSEL | pin, source | Select pin source: 0=CPU, 1=Timer0..7=Timer0-7 |
| 0x8 | EVEN | timer, mask | Enable timer events (rise/fall/capture) |
| 0x9 | SWAP | — | Atomic program bank swap (staging → active) |
| 0xA | VERIFY | rd | rd = CRC32 of staging bank |
| 0xB | CAPRD | rd, timer | Read timer capture FIFO → rd |
| 0xC | JALR | rd, rs1 | Register indirect jump (rd = PC+2, PC = rs1) |
| 0xF | HALT | — | Stop CPU execution |

### Timer Modes (for TCFG)

| Value | Mode | Description |
|-------|------|-------------|
| 0x00 | OFF | Timer disabled |
| 0x01 | COUNT_UP | 16-bit up counter (clock cycles) |
| 0x02 | COUNT_DOWN | 16-bit down counter |
| 0x03 | NCO_CLK | **NCO clock output** — 50% duty cycle square wave |
| 0x04 | NCO_VAR | Variable duty cycle NCO (uses compare register) |
| 0x05 | PWM | PWM output (compare = duty) |
| 0x08 | CAPTURE | Input capture on pin edge |
| 0x10 | MEASURE | Period/pulse width measurement |

### NCO Frequency Formula

```
f_out = (tuning × 50MHz) / 2^24

Where tuning is 24-bit value written via TUNING instruction.
Resolution at 50MHz: 50MHz / 2^24 ≈ 2.98 Hz
```

**Common NCO Tunings @ 50MHz:**

| Protocol | Frequency | Tuning (hex) | Tuning (dec) |
|----------|-----------|--------------|--------------|
| UART 3 Mbps | 3,000,000 | 0x0F5C29 | 10,065,321 |
| UART 115200 | 115,200 | 0x0005EB | 1,515 |
| SPI 25 MHz | 25,000,000 | 0x800000 | 8,388,608 |
| SPI 12.5 MHz | 12,500,000 | 0x400000 | 4,194,304 |
| I²C 100 kHz | 100,000 | 0x0051EB | 33,259 |
| I²C 400 kHz | 400,000 | 0x0147AE | 133,038 |
| I2S MCLK 12.288M | 12,288,000 | 0x2D1A94 | 2,960,788 |
| I2S BCLK 3.072M | 3,072,000 | 0x0B46A5 | 739,237 |
| I2S LRCK 48k | 48,000 | 0x00199A | 6,554 |
| CAN 500 kbps | 500,000 | 0x01999A | 104,858 |
| USB LS 1.5 Mbps | 1,500,000 | 0x07AE14 | 503,316 |

---

## 2. Timer Coprocessor (`timer_coproc.v`)

### Architecture
- **8 independent timers** (Timer 0-7), one per pin
- Each timer has:
  - **24-bit NCO phase accumulator** — generates precise clock frequencies
  - **16-bit counter** — counts cycles, captures, or measures
  - **Capture FIFO** — stores timestamp on pin edge events
  - **Compare register** — for PWM duty cycle or compare match
  - **Event system** — rising edge, falling edge, capture complete
  - **Mode register** — selects timer function

### Timer Register Map (per timer, 16 bytes = 8 words)

| Offset | Register | Description |
|--------|----------|-------------|
| 0x0 | NCO_INC_LOW | NCO phase increment [7:0] |
| 0x1 | NCO_INC_MID | NCO phase increment [15:8] |
| 0x2 | NCO_INC_HIGH | NCO phase increment [23:16] |
| 0x3 | CONFIG | Mode, enable, polarity |
| 0x4 | COMPARE | Compare value (PWM duty, compare match) |
| 0x5 | COUNTER | Counter value (read/write) |
| 0x6 | CAPTURE | Capture FIFO read |
| 0x7 | EVENTS | Event status/clear |

### NCO Operation (Mode NCO_CLK)
```
phase_accumulator += tuning  (every clock cycle)
NCO output = phase_accumulator[23]  (MSB = 50% duty square wave)
```

This generates a **jitter-free hardware clock** on the pin — no CPU involvement needed.

### Capture/Measure Operation
- **CAPTURE mode**: On pin edge (configured via EVEN), current counter value pushed to FIFO
- **MEASURE mode**: Counter runs continuously; on edge, delta from previous edge stored
- CPU reads via `CAPRD` instruction

---

## 3. Pin Matrix (`pin_matrix.v`)

### Architecture
- **8×8 crossbar**: Each of 8 pins can source from CPU or any of 8 timers
- **Per-pin configuration**:
  - **Source select** (4 bits): 0=CPU, 1-8=Timer0-7
  - **Direction** (1 bit): 1=output, 0=input
  - **Pull up/down** (2 bits): 00=none, 01=pull-up, 10=pull-down
  - **Output enable** (1 bit): Gates CPU output to pin

### Pin Register Map (memory-mapped at 0xF100)

| Addr | Register | Bits | Description |
|------|----------|------|-------------|
| 0x0 | DIR | [7:0] | Pin directions (1=out) |
| 0x1 | OUT | [7:0] | CPU pin output values |
| 0x2 | IN | [7:0] | Pin input values (read-only) |
| 0x3 | OE | [7:0] | Output enables |
| 0x4 | SEL_LO | [15:0] | Pins 0-3 source select (4 bits each) |
| 0x5 | SEL_HI | [15:0] | Pins 4-7 source select (4 bits each) |
| 0x6 | PULL | [15:0] | Pull config (2 bits per pin) |
| 0x7 | RISE | [7:0] | Rising edge detect status |
| 0x8 | FALL | [7:0] | Falling edge detect status |

### Pin Source Select Values

| Value | Source |
|-------|--------|
| 0x0 | CPU (OUT register) |
| 0x1 | Timer 0 NCO/PWM |
| 0x2 | Timer 1 NCO/PWM |
| 0x3 | Timer 2 NCO/PWM |
| 0x4 | Timer 3 NCO/PWM |
| 0x5 | Timer 4 NCO/PWM |
| 0x6 | Timer 5 NCO/PWM |
| 0x7 | Timer 6 NCO/PWM |
| 0x8 | Timer 7 NCO/PWM |

---

## 4. Host Interface (`host_if.v`)

### SPI Slave Protocol
- **64-bit commands**, MSB first
- **Commands**:
  - `0x01` WRITE: Write 32-bit data to program RAM at 16-bit address
  - `0x02` READ: Read back (reserved)
  - `0x03` RUN: Start CPU with program length = address[7:0]

### Command Format (64 bits)
```
[63:32] = Data (32 bits)
[31:16] = Address (16 bits)
[15:8]  = Command (8 bits)
[7:0]   = Padding (ignored)
```

### Firmware Loading Sequence
1. Host sends WRITE commands to load program words into RAM
2. Host sends RUN command with program length
3. Host interface triggers `cpu_start` pulse
4. CPU begins execution from PC=0

---

## 5. Program Memory

### ASIC (IHP SG13G2)
- **2 × RM_IHPSG13_1P_1024x16_c2_bm_bist** SRAM macros
- **Bank A (active)**: 1024 × 16-bit = 2 KB
- **Bank B (staging)**: 1024 × 16-bit = 2 KB
- **Boot ROM**: 512 × 16-bit = 1 KB (factory firmware)
- **Total**: 4 KB active + 2 KB staging + 1 KB boot
- **Atomic bank swap** via `SWAP` instruction

### FPGA (Basys3 Artix-7)
- **Block RAM**: 2048 × 16-bit = 4 KB (single bank)
- **No bank swap** — direct write via SPI

---

## 6. Data Flow Examples

### UART TX (3 Mbps) — Hybrid Approach
```
Setup (once):
  TUNING Timer0, 0x0F5C29  ; 3M baud @ 50MHz
  TCFG   Timer0, NCO_CLK   ; Hardware baud clock
  PINSEL Pin0, Timer0      ; Pin 0 = Timer0 NCO output
  DIR    Pin0, 1           ; Pin 0 = output

Per byte (CPU bit-bang):
  OUT Pin0, 0              ; Start bit
  WAIT Timer0, 16          ; Wait 1 bit time (16 NCO cycles)
  OUT Pin0, bit0           ; Data bit 0
  WAIT Timer0, 16
  ... (8 bits) ...
  OUT Pin0, 1              ; Stop bit
  WAIT Timer0, 16
```

**Key**: Clock is **hardware** (jitter-free), data is **firmware** (flexible).

### SPI Master (25 MHz) — Pure Firmware
```
Setup:
  TUNING Timer0, 0x800000  ; 25MHz @ 50MHz (NCO)
  TCFG   Timer0, NCO_CLK
  PINSEL SCK, Timer0       ; SCK = hardware clock
  DIR    MOSI, 1; DIR CS, 1; DIR MISO, 0

Per transaction:
  OUT CS, 0                ; Assert CS
  FOR 8 bits:
    OUT MOSI, bit          ; Drive MOSI
    WAITE Timer0, RISE     ; Wait SCK rising (sample MISO)
    IN  MISO               ; Read MISO
    WAITE Timer0, FALL     ; Wait SCK falling (drive next)
  OUT CS, 1                ; Deassert CS
```

### I²C Master (100 kHz) — Open-Drain Emulation
```
Setup:
  TUNING Timer0, 0x0051EB  ; 100kHz SCL
  TCFG   Timer0, NCO_CLK
  PINSEL SCL, Timer0       ; SCL = hardware clock
  DIR    SDA, 0            ; SDA = input (open-drain)
  OUT    SDA, 1            ; Release SDA (pull-up holds high)

Start condition:
  DIR SDA, 1; OUT SDA, 0   ; Drive SDA low while SCL high
  WAIT Timer0, 4

Write bit:
  DIR SDA, 1; OUT SDA, bit ; Drive SDA
  WAITE Timer0, RISE       ; Wait SCL rising
  WAITE Timer0, FALL       ; Wait SCL falling

Read bit:
  DIR SDA, 0               ; Release SDA (input)
  WAITE Timer0, RISE       ; Wait SCL rising
  IN  SDA                  ; Sample SDA
  WAITE Timer0, FALL       ; Wait SCL falling
```

---

## 7. Memory Map (CPU View)

| Address Range | Name | Access | Description |
|---------------|------|--------|-------------|
| 0x0000-0x07FF | Program RAM (Bank A) | R (fetch) | Active firmware (2048 × 16) |
| 0x0800-0x0FFF | Program RAM (Bank B) | R/W | Staging bank (ASIC only) |
| 0x1000-0x11FF | Boot ROM | R | Factory firmware |
| 0xF000-0xF00F | Timer 0 | RW | Timer 0 registers |
| 0xF010-0xF01F | Timer 1 | RW | Timer 1 registers |
| 0xF020-0xF02F | Timer 2 | RW | Timer 2 registers |
| 0xF030-0xF03F | Timer 3 | RW | Timer 3 registers |
| 0xF040-0xF04F | Timer 4 | RW | Timer 4 registers |
| 0xF050-0xF05F | Timer 5 | RW | Timer 5 registers |
| 0xF060-0xF06F | Timer 6 | RW | Timer 6 registers |
| 0xF070-0xF07F | Timer 7 | RW | Timer 7 registers |
| 0xF100-0xF10F | Pin Matrix | RW | Pin configuration |
| 0xF200-0xF207 | Host Interface | R | Status, CRC, version |

---

## 8. Area & Performance (ASIC: IHP SG13G2 130nm)

| Metric | Value |
|--------|-------|
| **Std Cells** | 9,110 |
| **Area** | 68,500 μm² |
| **TT Budget** | 32K cells (28.5% used) |
| **Max Frequency** | 50 MHz (20ns period) |
| **Pipeline** | 4-stage, 1 instr/cycle (ideal) |
| **Timer Resolution** | 20ns (1 cycle @ 50MHz) |
| **NCO Resolution** | 24-bit (50MHz/2^24 ≈ 3 Hz) |
| **Program Memory** | 4 KB (2048 instructions) |

---

## 9. Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| 16-bit ISA | Small opcode space, fits 4KB program RAM |
| 4-stage pipeline | Balance of frequency vs complexity |
| Opcode 0xF for custom | Clean separation from ALU/branch |
| 8 timers | Matches 8 pins, enables multi-protocol |
| 24-bit NCO | ~3 Hz resolution at 50MHz, covers all common baud rates |
| SPI host interface | Standard, low pin count, works with any MCU |
| Memory-mapped I/O | No LOAD/STORE instructions needed |
| Pin matrix crossbar | Dynamic pin reassignment mid-protocol |
| Hybrid clock/data | Hardware NCO for clocks, CPU for data = best of both |

---

## 10. Limitations & Workarounds

| Limitation | Impact | Workaround |
|------------|--------|------------|
| No hardware interrupts | Can't preempt | Poll events in main loop, use WAITE |
| 8-bit branch offset | ±127 instructions | Use JALR for far jumps |
| No MUL/DIV | Math slower | Use shifts, or software routines |
| No LOAD/STORE | Memory via I/O | Memory-mapped peripheral addresses |
| Single program bank (FPGA) | 4 KB limit | ASIC has bank swap |
| OpenSTA 2.0 too old | Can't STA locally | Use TT's qualified OpenSTA |

---

## 11. Verification Status

| Testbench | Protocol | Status |
|-----------|----------|--------|
| `tb_emu_uart.v` | UART TX/RX @ 3Mbps | ✅ PASS |
| `tb_emu_spi_master.v` | SPI Master @ 25MHz | ✅ PASS |
| `tb_emu_i2c_master.v` | I²C Master @ 100kHz | ✅ PASS |
| `tb_halt_test.v` | HALT instruction | ✅ PASS |
| `tb_wait_wait.v` | WAIT/WAITE instructions | ✅ PASS |
| `tb_branch.v` | Branch instructions | ✅ PASS |

---

*This architecture enables ONE chip to become ANY protocol — the protocol lives in YOUR firmware, not in fixed silicon.*
