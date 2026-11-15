# Protocol Discovery Core — Usage & Testing Guide

## Quick Start

```bash
cd /home/muqtada/Documents/progleprot

# Run all simulation tests
make test_all      # Runs all milestones M1-M6 + PS/2
make sweep         # M1: parameter sweep (4 FRAC/BIN_W combos)

# Individual milestones
make m1            # M1: histogram/peak detect
make m2            # M2: UART auto-baud + framing
make m3            # M3: SPI + I²C detection
make m4            # M4: Fingerprint matching
make m5            # M5: Pin-role discovery
make m6            # M6: Full closed-loop (discovery→compile→replay)
make ps2           # PS/2 detector test
```

## Milestone Test Commands

```bash
# M1: Edge interval + histogram + peak detect
make m1

# M1 Parameter Sweep (FRAC/BIN_W)
make sweep

# M2: UART auto-baud + framing
make m2

# M3: SPI + I²C detection (with encoding layer support)
make m3

# M4: Fingerprint matching + ranked output
make m4

# M5: Pin-role discovery
make m5

# M6: Full closed-loop (discovery → compile → replay)
make m6

# PS/2 detector
make ps2
```

## Key Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `CNT_W` | 16 | Interval counter width (cycles) |
| `FRAC` | 1 | Log bucket fractional bits (1=32 bins, 2=64 bins) |
| `BIN_W` | 8 | Histogram counter bits (6/8/12) |
| `NUM_PINS` | 8 | Input pins monitored |
| `N_COLLECT` | 1024 | Intervals collected per scan |
| `MAX_PRINTS` | 16 | Fingerprint ROM entries |

## Encoding Layer Modes (M8)

The encoding layer (`encoding_layer.v`) sits before protocol detectors and supports:

| Mode | Value | Description |
|------|-------|-------------|
| NRZ | 2'd0 | Direct bit mapping (default) |
| NRZI | 2'd1 | Transition = 0, No transition = 1 |
| Manchester | 2'd2 | High→low = 0, Low→high = 1 |
| Stuffing | 2'd3 | Bit stuffing (CAN/USB) |

**Inputs:**
- `ch0_enc_mode[1:0]` - Encoding mode for channel 0 (SPI data line)
- `ch0_stuff_after[3:0]` - Stuff after N consecutive same bits (0=disable)

**Usage in m3_top/m6_top:**
- Applied to SPI data line (pin 0 / pins_in[0]) only
- I2C uses raw signals directly (no encoding layer needed)

## Pin Mapping (Testbench)

| Pin | M5/M6 Role | Signal |
|-----|------------|--------|
| 0 | CLK | SPI SCK / I²C SCL (ch0) |
| 1 | DATA | SPI MOSI/MISO / I²C SDA (ch0) |
| 2 | CLK | I²C SCL / SPI SCK (ch1) |
| 3 | CLK | I²C SDA / CS |
| 4 | CS | SPI CS (active low) |
| 5 | TX | UART TX |
| 6 | CS | Additional CS |
| 7 | CS | Additional CS |

## Adding Custom Fingerprints

Edit `rtl/fingerprint_rom.v`:
```verilog
// Format: {proto_id, pattern_len, pattern_bits}
// proto_id: 1=SPI, 2=I²C, 3=UART, 4=PS/2
// Add entries to the case statement
```

## Running with Different Clocks

The core assumes a single clock domain. For different sample rates:
```bash
iverilog -PCNT_W=20 ...  # Wider counter for slower clocks
iverilog -PFRAC=2 ...    # More histogram buckets for precision
```

## Debug Output

Key signals to monitor:
- `scan_done` — interval collection complete
- `list_done` — ranked protocol list ready
- `result_valid/result_proto/result_conf/result_rank` — top hypotheses
- `replay_done/replay_error` — sequencer status
- `prog_len` — compiled program length
- `seq_pc` — sequencer program counter

## Expected Outputs

- **M1**: PASS A-E (histogram/peak tests)
- **M2**: PASS all UART configs (7/8 bits, N/E/O parity, various baud)
- **M3**: PASS SPI + I²C frame detection
- **M4**: PASS fingerprint matching with confidence scores
- **M5**: PASS pin role assignment (CLK/DATA/CS/TX)
- **M6**: PASS full discovery→compile→replay cycle
- **PS/2**: PASS frame detection with parity check

## Known Limits (from architecture.md)

- Minimum ~16 clock cycles/bit for reliable baud detection
- Back-to-back frames need ≥4 bit-times idle gap
- 2 stop bits indistinguishable from 1 stop + idle
- 7E1/8O1 and 7N1/8N1 bit-level ambiguous; shortest frame wins
- Jitter tolerance: ±10% per edge; breaks at ±20%
- Glitch tolerance: 1/2000 cycles; breaks at 1/500

## Area Budget

| Block | Est. Cells |
|-------|------------|
| M1 (edge_interval + histogram + peak) | ~1.7K |
| M2 (UART framer + auto-baud) | ~4.7K |
| M3 (SPI + I²C detect) | ~2.0K |
| M4 (fingerprint ROM + matcher) | ~2.0K |
| M5 (pin role discovery) | ~2.0K |
| M6 (sequencer + compiler) | ~4.0K |
| Encoding layer | ~1.5K |
| **Total** | **~20K** (~32K budget, 37% margin) |

## Next Steps (Roadmap)

1. **M7** - Synthesis area check with Yosys (`make yosys_area`)
2. **M8** - Full encoding layer integration (NRZI, Manchester, stuffing for CAN/USB)
3. **M9** - Vivado P&R (`make vivado_proj`, see docs/VIVADO.md)
4. **M10** - Stretch: 10BASE-T Ethernet (Manchester + fast clock)
