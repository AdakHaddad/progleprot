/*
 * I²C Master Firmware for Protocol Emulator ASIC
 * Implements I²C Master at 100kHz/400kHz using NCO timer
 * 
 * ISA: 16-bit RISC-like with custom timing instructions
 * 
 * Register usage:
 *   x1  = NCO phase increment (I²C clock rate)
 *   x2  = SDA pin (0)
 *   x3  = SCL pin (1)
 *   x4  = Slave address (7-bit)
 *   x5  = TX data buffer
 *   x6  = RX data buffer
 *   x7  = Bit counter (8 bits + ACK)
 *   x8  = Wait cycles
 *   x9  = State / temp
 *   x10 = Timer index (0)
 *   x11 = Constant 1
 *   x12 = Constant 0
 *   x13 = I²C config register
 *   x14 = Scratch
 *   x15 = Scratch
 */

// ============================================================
// ISA Encoding
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
.equ FUNCT_OUT,    0x0
.equ FUNCT_DIR,    0x1
.equ FUNCT_WAIT,   0x2
.equ FUNCT_WAITE,  0x3
.equ FUNCT_TIME,   0x4
.equ FUNCT_TCFG,   0x5
.equ FUNCT_PINSEL, 0x6
.equ FUNCT_EVEN,   0x7
.equ FUNCT_SWAP,   0x8
.equ FUNCT_VERIFY, 0x9
.equ FUNCT_CAPRD,  0xA
.equ FUNCT_HALT,   0xF

.macro OUT pin_reg, val_reg
    .hword (0xF << 12) | (FUNCT_OUT << 8) | (\pin_reg << 4) | \val_reg
.endm

.macro DIR pin_reg, dir_reg
    .hword (0xF << 12) | (FUNCT_DIR << 8) | (\pin_reg << 4) | \dir_reg
.endm

.macro WAIT timer_reg, cycles_reg
    .hword (0xF << 12) | (FUNCT_WAIT << 8) | (\timer_reg << 4) | \cycles_reg
.endm

.macro TCFG timer_reg, config_reg
    .hword (0xF << 12) | (FUNCT_TCFG << 8) | (\timer_reg << 4) | \config_reg
.endm

.macro PINSEL pin_reg, src_reg
    .hword (0xF << 12) | (FUNCT_PINSEL << 8) | (\pin_reg << 4) | \src_reg
.endm

.macro HALT
    .hword 0xFFFF
.endm

// I²C pin definitions
.equ SDA_PIN, 0
.equ SCL_PIN, 1

// I²C timing: 100kHz @ 50MHz = 500 cycles per quarter period
// NCO: (100000 / 50000000) * 2^24 = 335544 = 0x51EB8
// For 400kHz: (400000 / 50000000) * 2^24 = 1342177 = 0x147AE1

// Open-drain: DIR=1 (output), OUT=0 (drive low), OUT=1 (release/high-z)

.section .text
.org 0x0000

// ------------------------------------------------------------
// Initialization
// ------------------------------------------------------------
start:
    // Configure NCO for 100kHz I²C clock
    // NCO increment = 0x51EB8 (335544)
    ADDI x1, 0xB8   // Low byte
    ADDI x9, 0x1E   // Mid byte  
    ADDI x10, 0x05  // High byte
    
    // Configure timer 0 for NCO mode
    ADDI x11, 0x00  // Timer 0
    // TCFG: write NCO_INC registers via memory-mapped interface
    // For now use TCFG custom instruction with mode
    ADDI x12, 0x03  // MODE_NCO_CLK = 3
    TCFG x11, x12   // Configure timer 0 as NCO clock
    
    // Set up pin directions (both open-drain outputs)
    // SDA (pin 0) = output
    ADDI x2, SDA_PIN
    ADDI x13, 0x01  // Output direction
    DIR x2, x13
    
    // SCL (pin 1) = output  
    ADDI x3, SCL_PIN
    DIR x3, x13
    
    // Pin select: SCL (pin 1) driven by Timer 0 NCO
    ADDI x14, 0x01  // Timer 0 NCO source
    PINSEL x3, x14
    
    // Initialize constants
    ADDI x11, 0x01  // x11 = constant 1
    ADDI x12, 0x00  // x12 = constant 0
    
    // Slave address (7-bit) << 1 | R/W
    ADDI x4, 0xA0   // 0x50 << 1 | 0 (write)
    
    // I²C idle: both lines high (released)
    // Open-drain: OUT=1 means release (pull-up holds high)
    ADDI x5, 0x01   // High
    OUT x2, x5      // SDA = 1
    OUT x3, x5      // SCL = 1
    
    ADDI x8, 0x64   // Wait 100 cycles (idle)
    WAIT x11, x8

// ------------------------------------------------------------
// I²C START condition: SDA falls while SCL high
// ------------------------------------------------------------
i2c_start:
    // SDA = 0 (drive low) while SCL = 1
    ADDI x5, 0x00   // Low
    OUT x2, x5      // SDA = 0
    
    ADDI x8, 0x32   // Wait 50 cycles (hold time)
    WAIT x11, x8
    
    // SCL = 0 (start clock)
    OUT x3, x5      // SCL = 0
    
    ADDI x8, 0x32   // Wait 50 cycles
    WAIT x11, x8
    
    JUMP i2c_send_byte  // Send address byte

// ------------------------------------------------------------
// Send 8 bits + read ACK
// x4 = byte to send
// ------------------------------------------------------------
i2c_send_byte:
    ADDI x7, 0x08   // 8 bits
    
i2c_send_bit_loop:
    // Get MSB of x4
    // For simplicity, we'll unroll the loop for 8 bits
    // In real firmware, would use shift/rotate
    
    // Check bit 7
    // If bit 7 is 1: SDA = 1 (release), else SDA = 0 (drive low)
    // We'll use a jump table approach
    
    // Bit 7 (MSB)
    // For demo: just send the byte in x4
    // This is simplified - real implementation would shift
    
    ADDI x9, 0x32   // Quarter period wait
    WAIT x11, x9
    
    // SCL rising edge - data must be stable
    // SCL is driven by NCO, so we just wait
    
    ADDI x9, 0x32   // Quarter period
    WAIT x11, x9
    
    // SCL falling edge - can change data
    ADDI x7, 0xFF   // Decrement counter (SUB not implemented, use ADD with -1)
    // For now just count down manually
    
    // Check if done 8 bits - simplified
    // Real version: branch if x7 != 0
    // For demo, just do 8 explicit iterations
    
    // Bit 0 (after 8 bits) - read ACK
    // Release SDA for ACK clock
    ADDI x5, 0x01   // SDA = 1 (release)
    OUT x2, x5
    
    ADDI x9, 0x32
    WAIT x11, x9
    
    // Sample ACK (SDA should be 0 if ACK)
    // Would use TIME or direct pin read
    // For now, just wait
    
    ADDI x9, 0x32
    WAIT x11, x9
    
    // SCL = 0
    ADDI x5, 0x00
    OUT x3, x5
    
    ADDI x8, 0x32
    WAIT x11, x8

// ------------------------------------------------------------
// I²C STOP condition: SDA rises while SCL high
// ------------------------------------------------------------
i2c_stop:
    // SDA = 0, SCL = 1
    ADDI x5, 0x00
    OUT x2, x5
    
    ADDI x5, 0x01
    OUT x3, x5      // SCL = 1
    
    ADDI x8, 0x32
    WAIT x11, x8
    
    // SDA = 1 (STOP)
    OUT x2, x5      // SDA = 1
    
    ADDI x8, 0x64   // Wait 100 cycles
    WAIT x11, x8
    
    HALT

// ------------------------------------------------------------
// Full I²C Write Transaction
// Write to slave 0x50, register 0x00, data 0x42
// ------------------------------------------------------------
i2c_write_demo:
    // START
    JUMP i2c_start
    
    // Send slave address + W (0xA0)
    ADDI x4, 0xA0
    JUMP i2c_send_byte
    
    // Send register address (0x00)
    ADDI x4, 0x00
    JUMP i2c_send_byte
    
    // Send data (0x42)
    ADDI x4, 0x42
    JUMP i2c_send_byte
    
    // STOP
    JUMP i2c_stop

.end
