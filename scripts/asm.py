#!/usr/bin/env python3
"""
Simple Assembler for Protocol Emulator ISA
Supports the custom 16-bit instruction set
"""

import argparse
import sys
import re

# ISA Opcode Map
OPCODES = {
    # ALU (imm8)
    'ADD':  0x0, 'SUB':  0x1, 'AND':  0x2, 'OR':   0x3,
    'XOR':  0x4, 'SHL':  0x5, 'SHR':  0x6, 'CMP':  0x7,
    'ADDI': 0x8, 'SUBI': 0x9, 'ANDI': 0xA, 'ORI':  0xB,
    'XORI': 0xC, 'SHLI': 0xD, 'SHRI': 0xE, 'CMPI': 0xF,
    
    # Memory/Load-Store (not yet implemented)
    'LOAD': 0xC, 'STORE': 0xD,
    
    # Branch (offset8)
    'BEQZ': 0xE0, 'BNEZ': 0xE1, 'BLTZ': 0xE2, 'BGEZ': 0xE3,
    'JAL':  0xE4, 'JALR': 0xE5,
    
    # Custom/Timing (opcode 0xF)
    'WAIT':  0xF0, 'WAITE': 0xF1, 'SYNC':  0xF2,
    'PINRD': 0xF3, 'PINWR': 0xF4, 'TIMRD': 0xF5,
    'TIMWR': 0xF6, 'HALT':  0xFF,
}

# Register names
REGS = {f'R{i}': i for i in range(16)}
REGS.update({f'X{i}': i for i in range(16)})

def parse_operand(tok):
    """Parse register or immediate"""
    tok = tok.strip().strip(',')
    if tok.upper() in REGS:
        return ('reg', REGS[tok.upper()])
    # Immediate
    try:
        if tok.startswith('0x') or tok.startswith('0X'):
            val = int(tok, 16)
        elif tok.startswith('0b'):
            val = int(tok[2:], 2)
        else:
            val = int(tok)
        return ('imm', val & 0xFFFF)
    except ValueError:
        raise ValueError(f"Invalid operand: {tok}")

def assemble_line(line, pc, labels):
    """Assemble single instruction line"""
    # Remove comments
    line = line.split(';')[0].strip()
    if not line:
        return None
    
    # Check for label
    label_match = re.match(r'(\w+):', line)
    if label_match:
        label = label_match.group(1)
        labels[label] = pc
        line = line[label_match.end():].strip()
        if not line:
            return None
    
    # Parse instruction
    parts = line.split(None, 1)
    mnemonic = parts[0].upper()
    args_str = parts[1] if len(parts) > 1 else ''
    
    # Parse operands
    args = [a.strip() for a in args_str.split(',')] if args_str else []
    
    if mnemonic not in OPCODES:
        raise ValueError(f"Unknown instruction: {mnemonic}")
    
    opcode = OPCODES[mnemonic]
    
    # Encode based on instruction type
    if mnemonic in ['ADD', 'SUB', 'AND', 'OR', 'XOR', 'SHL', 'SHR', 'CMP']:
        # RD, RS1, RS2/imm8
        rd = parse_operand(args[0])[1]
        rs1 = parse_operand(args[1])[1]
        op3 = parse_operand(args[2])
        if op3[0] == 'reg':
            # Register form: funct in bits 3:0
            funct = op3[1]
            return (opcode << 12) | (rd << 8) | (rs1 << 4) | funct
        else:
            # Immediate form: imm8 in bits 7:0
            imm8 = op3[1] & 0xFF
            return (opcode << 12) | (rd << 8) | (rs1 << 4) | 0x8 | (imm8 >> 4)  # Simplified
            
    elif mnemonic in ['ADDI', 'SUBI', 'ANDI', 'ORI', 'XORI', 'SHLI', 'SHRI', 'CMPI']:
        # RD, RS1, imm8
        rd = parse_operand(args[0])[1]
        rs1 = parse_operand(args[1])[1]
        imm8 = parse_operand(args[2])[1] & 0xFF
        return (opcode << 12) | (rd << 8) | (rs1 << 4) | (imm8 >> 4)  # Simplified
        
    elif mnemonic in ['BEQZ', 'BNEZ', 'BLTZ', 'BGEZ']:
        # RS, offset8
        rs = parse_operand(args[0])[1]
        # Handle label or immediate
        if args[1].upper() in labels:
            offset = labels[args[1].upper()] - pc - 1
        else:
            offset = parse_operand(args[1])[1]
        offset8 = offset & 0xFF
        return (opcode << 12) | (rs << 8) | offset8
        
    elif mnemonic == 'JAL':
        # RD, offset8
        rd = parse_operand(args[0])[1]
        if args[1].upper() in labels:
            offset = labels[args[1].upper()] - pc - 1
        else:
            offset = parse_operand(args[1])[1]
        offset8 = offset & 0xFF
        return (opcode << 12) | (rd << 8) | offset8
        
    elif mnemonic == 'JALR':
        # RD, RS
        rd = parse_operand(args[0])[1]
        rs = parse_operand(args[1])[1]
        return (opcode << 12) | (rd << 8) | (rs << 4)
        
    elif mnemonic in ['WAIT', 'WAITE', 'SYNC']:
        # imm16
        imm16 = parse_operand(args[0])[1] if args else 0
        # Custom encoding: opcode 0xF, funct in bits 11:8, imm16 in separate word?
        # Simplified: pack into single word
        funct = {'WAIT': 0, 'WAITE': 1, 'SYNC': 2}[mnemonic]
        return (0xF << 12) | (funct << 8) | (imm16 & 0xFF)
        
    elif mnemonic in ['PINRD', 'PINWR', 'TIMRD', 'TIMWR']:
        # RD, RS, addr4
        rd = parse_operand(args[0])[1]
        rs = parse_operand(args[1])[1] if len(args) > 1 else 0
        addr4 = parse_operand(args[2])[1] if len(args) > 2 else 0
        funct = {'PINRD': 3, 'PINWR': 4, 'TIMRD': 5, 'TIMWR': 6}[mnemonic]
        return (0xF << 12) | (funct << 8) | (rd << 4) | (rs << 2) | (addr4 & 0x3)
        
    elif mnemonic == 'HALT':
        return 0xFFFF
        
    elif mnemonic == '.WORD':
        # Raw word
        return parse_operand(args[0])[1]
        
    elif mnemonic == '.ORG':
        # Origin - handled in pass 1
        return None
    
    return 0

def assemble(source_file, output_file):
    """Two-pass assembler"""
    with open(source_file, 'r') as f:
        lines = f.readlines()
    
    # Pass 1: collect labels
    labels = {}
    pc = 0
    for line in lines:
        line = line.split(';')[0].strip()
        if not line:
            continue
        label_match = re.match(r'(\w+):', line)
        if label_match:
            labels[label_match.group(1)] = pc
            line = line[label_match.end():].strip()
            if not line:
                continue
        if line.upper().startswith('.ORG'):
            pc = int(line.split()[1], 0)
            continue
        pc += 1
    
    # Pass 2: generate code
    pc = 0
    words = []
    for line in lines:
        line = line.split(';')[0].strip()
        if not line:
            continue
        if line.upper().startswith('.ORG'):
            pc = int(line.split()[1], 0)
            continue
        label_match = re.match(r'\w+:', line)
        if label_match:
            line = line[label_match.end():].strip()
            if not line:
                continue
        
        try:
            word = assemble_line(line, pc, labels)
            if word is not None:
                words.append(word & 0xFFFF)
                pc += 1
        except Exception as e:
            print(f"Error at PC={pc:04X}: {e}")
            print(f"  Line: {line}")
            return False
    
    # Write binary output
    with open(output_file, 'wb') as f:
        for w in words:
            f.write(bytes([(w >> 8) & 0xFF, w & 0xFF]))
    
    print(f"Assembled {len(words)} words -> {output_file}")
    return True

def main():
    parser = argparse.ArgumentParser(description='Assemble Protocol Emulator firmware')
    parser.add_argument('source', help='Assembly source file')
    parser.add_argument('-o', '--output', required=True, help='Output binary file')
    args = parser.parse_args()
    
    if not assemble(args.source, args.output):
        sys.exit(1)

if __name__ == '__main__':
    main()
