# Protocol Discovery Core

## How it works

The Protocol Discovery Core automatically detects and identifies unknown serial protocols on up to 8 input pins. It combines:

1. **Histogram-based timing analysis** — Measures edge intervals across all pins, builds log-spaced histograms, and finds peak bucket to estimate baud/clock rates
2. **Encoding layer** — Decodes NRZ, NRZI, Manchester, and bit-stuffed signals (CAN/USB) before protocol detection
3. **Protocol-specific detectors** — UART (auto-baud + framing), SPI (role discovery + CPOL/CPHA), I²C (START/STOP + addr+ACK), PS/2, CAN, USB LS
4. **Fingerprint matching** — Compares detected frame patterns against ROM library of known protocol signatures
5. **Pin-role discovery** — Auto-assigns CLK/DATA/CS/TX/RX/SDA/SCL roles via cross-correlation and signal pattern analysis
6. **Ranked output** — Emits prioritized protocol hypotheses with confidence scores (never a single silent guess)
7. **Sequencer compiler + replay** — Compiles top hypothesis into a PIO-inspired program and replays it on output pins for closed-loop verification

All logic is purely synchronous (single clock domain), no CPU, FSMs + ROM only. Target: IHP 130nm CMOS5L via Tiny Tapeout 8x4 tiles.

## How to test

```bash
# Run all simulation tests (M1-M6 + PS/2)
make test_all

# Individual milestones
make m1   # Histogram/peak detect
make m2   # UART auto-baud + framing
make m3   # SPI + I2C detection
make m4   # Fingerprint matching
make m5   # Pin-role discovery
make m6   # Full closed-loop
make ps2  # PS/2 detector

# Parameter sweep
make sweep
```

## External hardware

- **Target**: Tiny Tapeout IHP 130nm shuttle (March 2027)
- **FPGA prototype**: Basys3 (Artix-7) for hardware-in-the-loop testing
- **Test signals**: USB-UART adapter, SPI flash, I²C sensor, PS/2 keyboard, CAN transceiver
- **IO**: 8 input pins (monitored protocols) + bidirectional control/status on uio

## Pinout (TT 8x4 tiles)

| Pin | Function |
|-----|----------|
| ui[7:0] | 8 protocol signal inputs |
| uo[7:0] | Status: list_done, ambiguous, result_valid, replay_done, replay_error, scan_done, idle |
| uio[7:0] | In: clear, scan_start, replay_start, enc_mode[1:0], stuff_after[2:0] / Out: proto_id[3:0], rank[3:0] |

## Area Budget

- **Estimated**: ~20K cells (37% margin under 32K)
- **M7 Synthesis**: 6,649 cells (Yosys generic gates)

## Protocols Supported

| Protocol | Encoding | Status |
|----------|----------|--------|
| UART | NRZ + framing | ✅ M2 |
| SPI | Clocked (role + mode) | ✅ M3 |
| I²C | Open-drain START/STOP | ✅ M3 |
| PS/2 | Clocked + parity | ✅ M8 |
| CAN | NRZ + stuffing + CRC-15 | ✅ M8 |
| USB Low-Speed | NRZI + stuffing + CRC | ✅ M8 |
| 10BASE-T | Manchester | Stretch (M10) |
