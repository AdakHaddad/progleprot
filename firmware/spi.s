/*
 * SPI Master/Slave Firmware for Protocol Emulator ASIC
 * Implements SPI at 25MHz using NCO timer
 * 
 * Register usage:
 *   x1  = NCO phase increment (25MHz @ 50MHz = 0x8000000)
 *   x2  = TX pin (MOSI) = pin 0
 *   x3  = RX pin (MISO) = pin 1
 *   x4  = SCK pin = pin 2
 *   x5  = CS pin = pin 3
 *   x6  = Bit counter (8 bits)
 *   x7  = TX data buffer
 *   x8  = RX data buffer
 *   x9  = State machine
 *   x10 = Timer index (0)
 *   x11 = Mode (0=master, 1=slave)
 *   x12 = Scratch
 *   x13 = Constant 1
 *   x14 = Constant 0
 *   x15 = NCO config (MODE_NCO_CLK=3)
 */

// ============================================================
// ISA Encoding Macros
// ============================================================

// ADDI rd, imm8: opcode=8, rd=[11:8], imm8=[7:0]
.macro ADDI rd, imm
    .hword (0x8 << 12) | (\rd << 8) | (\imm & 0xFF)
.endm

// ADD rd, rs1, rs2: opcode=0, rd=[11:8], rs1=[7:4], rs2=[3:0]
.macro ADD rd, rs1, rs2
    .hword (0x0 << 12) | (\rd << 8) | (\rs1 << 4) | \rs2
.endm

// Custom: funct in [11:8], rs1 in [7:4], rs2 in [3:0]
.macro OUT pin_reg, val_reg
    .hword (0xF << 12) | (0x0 << 8) | (\pin_reg << 4) | \val_reg
.endm

.macro DIR pin_reg
    .hword (0xF << 12) | (0x1 << 8) | (\pin_reg << 4) | 0x0
.endm

.macro WAIT timer_reg, cycles_reg
    .hword (0xF << 12) | (0x2 << 8) | (\timer_reg << 4) | \cycles_reg
.endm

.macro TCFG timer_reg, config_reg
    .hword (0xF << 12) | (0x5 << 8) | (\timer_reg << 4) | \config_reg
.endm

.macro HALT
    .hword 0xFFFF
.endm

// ============================================================
// SPI Firmware - Master Mode
// ============================================================

.section .text
.org 0x0000

start:
    // Configure timer 0 for SPI clock (25MHz @ 50MHz)
    // NCO phase increment = (25_000_000 / 50_000_000) * 2^24 = 0x800000
    ADDI x1, 0x00   // x1 = NCO increment low byte
    ADDI x2, 0x00   // x2 = NCO increment mid byte  
    ADDI x3, 0x80   // x3 = NCO increment high byte (0x80)
    
    // Configure timer 0 NCO mode
    ADDI x4, 0x00   // x4 = timer 0 index
    ADDI x5, 0x03   // x5 = MODE_NCO_CLK (3)
    TCFG x4, x5     // Configure timer 0
    
    // Set up pin directions
    // MOSI (pin 0) = output
    ADDI x6, 0x00   // x6 = pin 0
    ADDI x7, 0x01   // x7 = 1 (output)
    DIR x6          // DIR pin 0, output (needs rs2 in register)
    
    // SCK (pin 2) = output (driven by NCO)
    ADDI x8, 0x02   // x8 = pin 2
    DIR x8          // DIR pin 2, output
    
    // CS (pin 3) = output
    ADDI x9, 0x03   // x9 = pin 3
    DIR x9          // DIR pin 3, output
    
    // MISO (pin 1) = input
    ADDI x10, 0x01  // x10 = pin 1
    ADDI x11, 0x00  // x11 = 0 (input)
    DIR x10         // DIR pin 1, input
    
    // Pin select: SCK (pin 2) = Timer 0 NCO
    ADDI x12, 0x01  // x12 = source 1 (Timer 0)
    // PINSEL pin 2, x12
    
    // Initialize state
    ADDI x13, 0x00  // x13 = state (0=idle)
    ADDI x14, 0x01  // x14 = constant 1
    ADDI x15, 0x00  // x15 = constant 0
    ADDI x11, 0x08  // x11 = bit count (8 bits)
    
    // CS high (inactive)
    ADDI x7, 0x01   // x7 = 1
    OUT x9, x7      // CS = high
    
    // Load TX data
    ADDI x7, 0xA5   // x7 = 0xA5 (test pattern)
    
    // CS low (active)
    ADDI x7, 0x00   // x7 = 0
    OUT x9, x7      // CS = low
    
    // SPI Master TX loop (8 bits)
    // Wait for SCK rising edge, then output bit
    // Wait for SCK falling edge, then sample MISO
    
spi_tx_loop:
    // Wait for SCK rising (NCO MSB goes high)
    ADDI x4, 0x00   // timer 0
    ADDI x12, 0x01  // wait 1 cycle (NCO toggle)
    WAIT x4, x12
    
    // Output current bit (MSB first)
    // Bit is in x7 MSB
    // For simplicity, just output bits of 0xA5
    // 0xA5 = 10100101
    
    // Bit 7 (MSB): 1
    ADDI x7, 0x01
    OUT x6, x7      // MOSI = 1
    
    // Wait for SCK falling
    WAIT x4, x12
    
    // Sample MISO (pin 1) - would read pin matrix here
    // For now just continue
    
    // Bit 6: 0
    ADDI x7, 0x00
    OUT x6, x7
    
    WAIT x4, x12
    WAIT x4, x12    // rising + falling
    
    // Bit 5: 1
    ADDI x7, 0x01
    OUT x6, x7
    
    WAIT x4, x12
    WAIT x4, x12
    
    // Bit 4: 0
    ADDI x7, 0x00
    OUT x6, x7
    
    WAIT x4, x12
    WAIT x4, x12
    
    // Bit 3: 0
    ADDI x7, 0x00
    OUT x6, x7
    
    WAIT x4, x12
    WAIT x4, x12
    
    // Bit 2: 1
    ADDI x7, 0x01
    OUT x6, x7
    
    WAIT x4, x12
    WAIT x4, x12
    
    // Bit 1: 0
    ADDI x7, 0x00
    OUT x6, x7
    
    WAIT x4, x12
    WAIT x4, x12
    
    // Bit 0 (LSB): 1
    ADDI x7, 0x01
    OUT x6, x7
    
    WAIT x4, x12
    WAIT x4, x12
    
    // CS high (inactive)
    ADDI x7, 0x01
    OUT x9, x7
    
    HALT

// ============================================================
// SPI Slave Mode (would be separate firmware)
// ============================================================
spi_slave:
    // Configure pins for slave
    // MOSI = input, MISO = output, SCK = input, CS = input
    // Use WAITE on SCK pin for clock edges
    // Use WAITE on CS pin for frame boundaries
    
    HALT

.end
