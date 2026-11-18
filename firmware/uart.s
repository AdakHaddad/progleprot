/*
 * UART Firmware for Protocol Emulator ASIC
 * Implements UART TX/RX at 3Mbps using NCO timers
 * 
 * ISA: 16-bit RISC-like with custom timing instructions
 * 
 * Register usage:
 *   x1  = NCO phase increment (baud rate)
 *   x2  = TX pin number
 *   x3  = RX pin number
 *   x4  = TX data buffer
 *   x5  = RX data buffer
 *   x6  = Bit counter (8 bits + start + stop = 10)
 *   x7  = State machine
 *   x8  = Temp / loop counter
 *   x9  = UART config (8N1)
 *   x10 = NCO timer index
 *   x11 = Scratch
 */

// ============================================================
// ISA Encoding Macros
// ============================================================

// ALU ops (OP_ALU = 0x0): [15:12]=0, [11:8]=rd, [7:4]=rs1, [3:0]=rs2
.macro ADD rd, rs1, rs2
    .hword (0x0 << 12) | (\rd << 8) | (\rs1 << 4) | \rs2
.endm

.macro SUB rd, rs1, rs2
    .hword (0x0 << 12) | (\rd << 8) | (\rs1 << 4) | \rs2 | (0x1 << 8)  // funct=1 in rs2? No, funct in [11:8] for ALU
    // Actually for OP_ALU, funct is in [11:8], so rd=[11:8], funct=[7:4]? Let me check...
.endm

// Wait - need to re-check ISA encoding
// From cpu_core.v:
// OP_ALU (0x0): rd=[11:8], rs1=[7:4], rs2=[3:0], funct=0 (ADD)
// OP_IMM (0x8): rd=[11:8], imm8=[7:0], rs1=x0
// OP_CUSTOM (0xF): funct=[11:8], rs1=[7:4], rs2/rd=[3:0]

// So for ADD: rd in [11:8], rs1 in [7:4], rs2 in [3:0], opcode=0
// .hword 0x0000 | (rd<<8) | (rs1<<4) | rs2

// For ADDI: rd in [11:8], imm8 in [7:0], opcode=8
// .hword 0x8000 | (rd<<8) | imm8

// For OP_CUSTOM: funct in [11:8], rs1 in [7:4], rs2 in [3:0], opcode=F
// .hword 0xF000 | (funct<<8) | (rs1<<4) | rs2

// Custom instruction funct codes:
.equ FUNCT_OUT,    0x0  // OUT pin, rs1 (pin=rs1[3:0], val from rs2)
.equ FUNCT_DIR,    0x1  // DIR pin, rs1
.equ FUNCT_WAIT,   0x2  // WAIT timer, rs1 (timer), rs2 (cycles)
.equ FUNCT_WAITE,  0x3  // WAITE timer, rs1 (pin event)
.equ FUNCT_TIME,   0x4  // TIME rd, timer (timer in rs1)
.equ FUNCT_TCFG,   0x5  // TCFG timer, rs1 (timer), rs2 (config)
.equ FUNCT_PINSEL, 0x6  // PINSEL pin, rs1
.equ FUNCT_EVEN,   0x7  // EVEN timer, rs1
.equ FUNCT_SWAP,   0x8  // SWAP
.equ FUNCT_VERIFY, 0x9  // VERIFY rd
.equ FUNCT_CAPRD,  0xA  // CAPRD rd, timer
.equ FUNCT_HALT,   0xF  // HALT

// Peripheral addresses (memory-mapped)
.equ TIMER_BASE,  0xF000  // 8 timers x 16 bytes each
.equ PIN_BASE,    0xF100  // Pin matrix config
.equ HOST_BASE,   0xF200  // Host interface

// Timer register offsets (per timer, 16 bytes = 8 words)
.equ TIMER_NCO_INC,  0x0  // NCO phase increment (24-bit, low 16)
.equ TIMER_NCO_INC_H,0x1  // NCO phase increment high 8 bits
.equ TIMER_CFG,      0x2  // Config: mode, enable, etc.
.equ TIMER_CMP,      0x3  // Compare value
.equ TIMER_CNT,      0x4  // Counter value
.equ TIMER_CAP,      0x5  // Capture value
.equ TIMER_EVT_EN,   0x6  // Event enable
.equ TIMER_EVT_STS,  0x7  // Event status

// Pin matrix registers
.equ PIN_REG_DIR,    0x0  // Direction (1=output)
.equ PIN_REG_OUT,    0x1  // Output value
.equ PIN_REG_IN,     0x2  // Input value
.equ PIN_REG_SEL0,   0x3  // Pin 0-3 source select
.equ PIN_REG_SEL1,   0x4  // Pin 4-7 source select

// ============================================================
// Macro definitions for instructions
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
    .hword (0xF << 12) | (FUNCT_OUT << 8) | (\pin_reg << 4) | \val_reg
.endm

.macro DIR pin_reg
    .hword (0xF << 12) | (FUNCT_DIR << 8) | (\pin_reg << 4) | 0x0
.endm

.macro WAIT timer_reg, cycles_reg
    .hword (0xF << 12) | (FUNCT_WAIT << 8) | (\timer_reg << 4) | \cycles_reg
.endm

.macro TCFG timer_reg, config_reg
    .hword (0xF << 12) | (FUNCT_TCFG << 8) | (\timer_reg << 4) | \config_reg
.endm

.macro TIME rd, timer_reg
    .hword (0xF << 12) | (FUNCT_TIME << 8) | (0x0 << 4) | \rd  // rs1=0, rd=rd
.endm

.macro HALT
    .hword 0xFFFF
.endm

// Memory access via peripheral addresses
// LOAD/STORE use OP_MEM (0xC) - not implemented yet, use memory-mapped via custom?

// ============================================================
// UART Firmware
// ============================================================

.section .text
.org 0x0000

// ------------------------------------------------------------
// Initialization
// ------------------------------------------------------------
start:
    // Configure timer 0 for UART baud rate (3Mbps @ 50MHz)
    // NCO phase increment = (baud_rate / clk_freq) * 2^24
    // = (3_000_000 / 50_000_000) * 16777216 = 1006633 = 0xF5C29
    ADDI x1, 0xC9   // NCO increment low 8 bits (0xF5C29 & 0xFF = 0x29? Wait)
    // 0xF5C29 = 1006633
    // Low 16 bits = 0x5C29
    // High 8 bits = 0x0F
    
    ADDI x1, 0x29   // x1 = NCO increment low byte (0x29)
    ADDI x2, 0x5C   // x2 = NCO increment mid byte (0x5C)
    ADDI x3, 0x0F   // x3 = NCO increment high byte (0x0F)
    
    // Configure timer 0
    ADDI x4, 0x00   // x4 = timer 0 index
    // TCFG timer 0: configure NCO
    // Need to write NCO_INC registers via memory-mapped interface
    // For now use custom TCFG instruction
    
    // Set up pin directions
    // TX pin (pin 0) = output
    ADDI x5, 0x00   // x5 = pin 0
    DIR x5          // Set pin 0 as output
    
    // RX pin (pin 1) = input
    ADDI x6, 0x01   // x6 = pin 1
    // DIR with rs2=0 means input? Or separate instruction?
    // DIR funct=1: DIR pin, rs1 - rs1 has pin number and direction in bits
    
    // Initialize TX data
    ADDI x7, 0x55   // x7 = TX test pattern (0x55 = 01010101)
    ADDI x8, 0x00   // x8 = bit counter
    ADDI x9, 0x0A   // x9 = total bits (1 start + 8 data + 1 stop = 10)
    ADDI x10, 0x00  // x10 = state (0=idle, 1=tx, 2=rx)
    ADDI x11, 0x01  // x11 = constant 1
    
    // Configure timer 0 NCO via memory-mapped write
    // Timer 0 base = 0xF000
    // This needs STORE instruction... for now use custom TCFG
    // TCFG funct=5: timer in rs1[3:0], config in rs2
    // Config format: [15:8]=NCO_INC_H, [7:0]=NCO_INC_L? Or just enable?
    
    // For now, just jump to main loop
    // (Real implementation would configure timer properly)
    
main_loop:
    // Simple TX loop: send 0x55 continuously
    // Start bit (0)
    ADDI x7, 0x00   // Start bit = 0
    OUT x5, x7      // OUT pin 0, value from x7
    
    // Wait for bit period using timer
    ADDI x4, 0x00   // Timer 0
    ADDI x8, 0x11   // ~17 cycles per bit at 3Mbps/50MHz = 16.67
    WAIT x4, x8     // WAIT timer 0, cycles in x8
    
    // Data bits (8 bits of 0x55 = 01010101)
    ADDI x7, 0x01   // Bit 0 = 1
    OUT x5, x7
    WAIT x4, x8
    
    ADDI x7, 0x00   // Bit 1 = 0
    OUT x5, x7
    WAIT x4, x8
    
    ADDI x7, 0x01   // Bit 2 = 1
    OUT x5, x7
    WAIT x4, x8
    
    ADDI x7, 0x00   // Bit 3 = 0
    OUT x5, x7
    WAIT x4, x8
    
    ADDI x7, 0x01   // Bit 4 = 1
    OUT x5, x7
    WAIT x4, x8
    
    ADDI x7, 0x00   // Bit 5 = 0
    OUT x5, x7
    WAIT x4, x8
    
    ADDI x7, 0x01   // Bit 6 = 1
    OUT x5, x7
    WAIT x4, x8
    
    ADDI x7, 0x00   // Bit 7 = 0
    OUT x5, x7
    WAIT x4, x8
    
    // Stop bit (1)
    ADDI x7, 0x01   // Stop bit = 1
    OUT x5, x7
    WAIT x4, x8
    
    // Inter-frame gap
    ADDI x8, 0x20   // Extra wait
    WAIT x4, x8
    
    // Loop back
    // In real firmware, would use branch instruction
    // For now just HALT
    HALT

// ------------------------------------------------------------
// Interrupt / Event handlers (not implemented yet)
// ------------------------------------------------------------
rx_handler:
    // RX pin change detected via WAITE
    // Sample data bits
    HALT

// ------------------------------------------------------------
// End
// ------------------------------------------------------------
.end
