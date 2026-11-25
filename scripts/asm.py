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
    # ALU (opcode 0x0): rd=[11:8], rs1=[7:4], rs2=[3:0], funct=0 (ADD only for now)
    'ADD':  (0x0, 'ALU'),
    'SUB':  (0x1, 'ALU'),
    'AND':  (0x2, 'ALU'),
    'OR':   (0x3, 'ALU'),
    'XOR':  (0x4, 'ALU'),
    'SLL':  (0x6, 'ALU'),
    'SRL':  (0x7, 'ALU'),
    'SRA':  (0x8, 'ALU'),
    'SLT':  (0x5, 'ALU'),
    
    # Immediate (opcode 0x8): rd=[11:8], imm8=[7:0] (sign-extended), rs1=x0
    'ADDI': (0x8, 'IMM'),
    'SUBI': (0x9, 'IMM'),
    'ANDI': (0xA, 'IMM'),
    'ORI':  (0xB, 'IMM'),
    'XORI': (0xC, 'IMM'),
    'SHLI': (0xD, 'IMM'),
    'SHRI': (0xE, 'IMM'),
    'SRAI': (0xF, 'IMM'),
    
    # Branch (opcodes 0xA-0xE): rs1=[11:8], offset8=[7:0]
    'BEQZ': (0xA, 'BR'),
    'BNEZ': (0xB, 'BR'),
    'BLTZ': (0xC, 'BR'),
    'BGEZ': (0xD, 'BR'),
    'JAL':  (0xE, 'JAL'),
    
    # Custom/Timing (opcode 0xF): funct=[11:8], rs1=[7:4], rs2/rd=[3:0]
    'OUT':     (0xF0, 'CUSTOM'),
    'DIR':     (0xF1, 'CUSTOM'),
    'WAIT':    (0xF2, 'CUSTOM'),
    'WAITE':   (0xF3, 'CUSTOM'),
    'TIME':    (0xF4, 'CUSTOM'),
    'TCFG':    (0xF5, 'CUSTOM'),
    'TUNING':  (0xF6, 'CUSTOM'),
    'PINSEL':  (0xF7, 'CUSTOM'),
    'EVEN':    (0xF8, 'CUSTOM'),
    'SWAP':    (0xF9, 'CUSTOM'),
    'VERIFY':  (0xFA, 'CUSTOM'),
    'CAPRD':   (0xFB, 'CUSTOM'),
    'JALR':    (0xFC, 'CUSTOM'),
    'HALT':    (0xFF, 'CUSTOM'),
    
    # Pseudo-instructions (handled specially)
    'LDI':     (0x100, 'PSEUDO'),
    'JMP':     (0x101, 'PSEUDO'),
    'CALL':    (0x102, 'PSEUDO'),
    'RET':     (0x103, 'PSEUDO'),
    'NOP':     (0x106, 'PSEUDO'),
    '.WORD':   (0x200, 'DIRECTIVE'),
    '.ORG':    (0x201, 'DIRECTIVE'),
}

# Register names (x0-x15)
REGS = {f'X{i}': i for i in range(16)}
REGS.update({f'R{i}': i for i in range(16)})

# Global for expression evaluation
CURRENT_EQUATES = {}

def parse_operand(tok):
    """Parse register or immediate"""
    tok = tok.strip().strip(',')
    if tok.upper() in REGS:
        return ('reg', REGS[tok.upper()])
    # Immediate - evaluate simple expressions (|, &, +, -, <<, >>)
    try:
        # Handle simple bitwise expressions
        if '|' in tok or '&' in tok or '+' in tok or '-' in tok or '<<' in tok or '>>' in tok:
            # Safe eval for simple expressions
            # Replace known constants
            for equ_name, equ_val in CURRENT_EQUATES.items():
                tok = tok.replace(equ_name, str(equ_val))
            val = eval(tok, {"__builtins__": {}}, {})
        elif tok.startswith('0x') or tok.startswith('0X'):
            val = int(tok, 16)
        elif tok.startswith('0b'):
            val = int(tok[2:], 2)
        else:
            val = int(tok)
        return ('imm', val & 0xFFFF)
    except ValueError:
        raise ValueError(f"Invalid operand: {tok}")

def sign_extend_8(val):
    """Sign-extend 8-bit value to 16 bits"""
    return val | 0xFF00 if (val & 0x80) else val

def assemble_line(line, pc, labels, equates, labels_upper=None):
    """Assemble single instruction line"""
    # Remove trailing ; comments
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
    
    # Substitute equates in args
    for i, arg in enumerate(args):
        for equ_name, equ_val in equates.items():
            # Replace whole word matches
            arg = re.sub(r'\b' + equ_name + r'\b', str(equ_val), arg)
        args[i] = arg
    
    if mnemonic not in OPCODES:
        raise ValueError(f"Unknown instruction: {mnemonic}")
    
    opcode, inst_type = OPCODES[mnemonic]
    
    # Encode based on instruction type
    if inst_type == 'ALU':
        # rd, rs1, rs2
        if len(args) < 3:
            raise ValueError(f"{mnemonic} needs 3 operands")
        rd = parse_operand(args[0])[1]
        rs1 = parse_operand(args[1])[1]
        rs2 = parse_operand(args[2])[1]
        # ALU: opcode=0, rd=[11:8], rs1=[7:4], rs2=[3:0], funct in rs2 for now (simplified)
        # Actually funct is separate - for ADD funct=0
        return (opcode << 12) | (rd << 8) | (rs1 << 4) | rs2
        
    elif inst_type == 'IMM':
        # rd, rs1, imm8 (rs1 is typically x0)
        if len(args) < 2:
            raise ValueError(f"{mnemonic} needs 2 operands")
        rd = parse_operand(args[0])[1]
        rs1 = parse_operand(args[1])[1] if len(args) > 2 else 0
        imm8 = parse_operand(args[-1])[1] & 0xFF
        # IMM: opcode=8-F, rd=[11:8], imm8=[7:0], rs1=x0
        return (opcode << 12) | (rd << 8) | imm8
        
    elif inst_type == 'BR':
        # rs1, label/offset
        if len(args) < 2:
            raise ValueError(f"{mnemonic} needs 2 operands")
        rs1 = parse_operand(args[0])[1]
        # Handle label or immediate
        if labels_upper and args[1].upper() in labels_upper:
            offset = labels_upper[args[1].upper()] - pc - 1
        else:
            offset = parse_operand(args[1])[1]
        offset8 = offset & 0xFF
        # BR: opcode=A-D, rs1=[11:8], offset8=[7:0]
        return (opcode << 12) | (rs1 << 8) | offset8
        
    elif inst_type == 'JAL':
        # rd, label/offset
        if len(args) < 2:
            raise ValueError(f"{mnemonic} needs 2 operands")
        rd = parse_operand(args[0])[1]
        if labels_upper and args[1].upper() in labels_upper:
            offset = labels_upper[args[1].upper()] - pc - 1
        else:
            offset = parse_operand(args[1])[1]
        offset8 = offset & 0xFF
        # JAL: opcode=E, rd=[11:8], offset8=[7:0]
        return (opcode << 12) | (rd << 8) | offset8
        
    elif inst_type == 'CUSTOM':
        # Custom instructions: funct in opcode low byte
        funct = opcode & 0xF
        if mnemonic == 'OUT':
            # OUT pin, val (rs1=pin, rs2=val)
            if len(args) < 2:
                raise ValueError("OUT needs pin, val")
            pin = parse_operand(args[0])[1]
            val = parse_operand(args[1])[1]
            return (0xF << 12) | (funct << 8) | (pin << 4) | (val & 0xF)
            
        elif mnemonic == 'DIR':
            # DIR pin, dir (rs1=pin, rs2=dir)
            if len(args) < 2:
                raise ValueError("DIR needs pin, dir")
            pin = parse_operand(args[0])[1]
            dir_val = parse_operand(args[1])[1]
            return (0xF << 12) | (funct << 8) | (pin << 4) | (dir_val & 0xF)
            
        elif mnemonic == 'WAIT':
            # WAIT timer, cycles (rs1=timer, rs2=cycles)
            if len(args) < 2:
                raise ValueError("WAIT needs timer, cycles")
            timer = parse_operand(args[0])[1]
            cycles = parse_operand(args[1])[1]
            return (0xF << 12) | (funct << 8) | (timer << 4) | (cycles & 0xF)
            
        elif mnemonic == 'WAITE':
            # WAITE timer, event_mask (rs1=timer, rs2=event)
            if len(args) < 2:
                raise ValueError("WAITE needs timer, event_mask")
            timer = parse_operand(args[0])[1]
            event = parse_operand(args[1])[1]
            return (0xF << 12) | (funct << 8) | (timer << 4) | (event & 0xF)
            
        elif mnemonic == 'TIME':
            # TIME rd, timer (rd=[3:0], rs1=timer)
            if len(args) < 2:
                raise ValueError("TIME needs rd, timer")
            rd = parse_operand(args[0])[1]
            timer = parse_operand(args[1])[1]
            return (0xF << 12) | (funct << 8) | (timer << 4) | rd
            
        elif mnemonic == 'TCFG':
            # TCFG timer, config (rs1=timer, rs2=config)
            if len(args) < 2:
                raise ValueError("TCFG needs timer, config")
            timer = parse_operand(args[0])[1]
            config = parse_operand(args[1])[1]
            return (0xF << 12) | (funct << 8) | (timer << 4) | (config & 0xF)
            
        elif mnemonic == 'TUNING':
            # TUNING timer, tuning_val (rs1=timer, rs2=tuning with bit8 for high/low)
            if len(args) < 2:
                raise ValueError("TUNING needs timer, value")
            timer = parse_operand(args[0])[1]
            tuning = parse_operand(args[1])[1]
            return (0xF << 12) | (funct << 8) | (timer << 4) | (tuning & 0xF)
            
        elif mnemonic == 'PINSEL':
            # PINSEL pin, source (rs1=pin, rs2=source)
            if len(args) < 2:
                raise ValueError("PINSEL needs pin, source")
            pin = parse_operand(args[0])[1]
            source = parse_operand(args[1])[1]
            return (0xF << 12) | (funct << 8) | (pin << 4) | (source & 0xF)
            
        elif mnemonic == 'EVEN':
            # EVEN timer, event_en (rs1=timer, rs2=event_en)
            if len(args) < 2:
                raise ValueError("EVEN needs timer, event_en")
            timer = parse_operand(args[0])[1]
            event_en = parse_operand(args[1])[1]
            return (0xF << 12) | (funct << 8) | (timer << 4) | (event_en & 0xF)
            
        elif mnemonic == 'SWAP':
            # SWAP (no operands)
            return (0xF << 12) | (funct << 8) | 0x00
            
        elif mnemonic == 'VERIFY':
            # VERIFY rd (rd=[3:0])
            if len(args) < 1:
                raise ValueError("VERIFY needs rd")
            rd = parse_operand(args[0])[1]
            return (0xF << 12) | (funct << 8) | rd
            
        elif mnemonic == 'CAPRD':
            # CAPRD rd, timer (rd=[3:0], rs1=timer)
            if len(args) < 2:
                raise ValueError("CAPRD needs rd, timer")
            rd = parse_operand(args[0])[1]
            timer = parse_operand(args[1])[1]
            return (0xF << 12) | (funct << 8) | (timer << 4) | rd
            
        elif mnemonic == 'JALR':
            # JALR rd, rs1 (rd=[3:0], rs1=[7:4])
            if len(args) < 2:
                raise ValueError("JALR needs rd, rs1")
            rd = parse_operand(args[0])[1]
            rs1 = parse_operand(args[1])[1]
            return (0xF << 12) | (funct << 8) | (rs1 << 4) | rd
            
        elif mnemonic == 'HALT':
            return 0xFFFF
            
    elif inst_type == 'PSEUDO':
        if mnemonic == 'LDI':
            # LDI rd, imm -> ADDI rd, x0, imm
            if len(args) < 2:
                raise ValueError("LDI needs rd, imm")
            rd = parse_operand(args[0])[1]
            imm8 = parse_operand(args[1])[1] & 0xFF
            return (0x8 << 12) | (rd << 8) | imm8
            
        elif mnemonic == 'JMP':
            # JMP label -> JAL x0, label
            if len(args) < 1:
                raise ValueError("JMP needs label")
            if labels_upper and args[0].upper() in labels_upper:
                offset = labels_upper[args[0].upper()] - pc - 1
            else:
                offset = parse_operand(args[0])[1]
            offset8 = offset & 0xFF
            return (0xE << 12) | (0 << 8) | offset8
            
        elif mnemonic == 'CALL':
            # CALL label -> JAL x14 (LR), label
            if len(args) < 1:
                raise ValueError("CALL needs label")
            if labels_upper and args[0].upper() in labels_upper:
                offset = labels_upper[args[0].upper()] - pc - 1
            else:
                offset = parse_operand(args[0])[1]
            offset8 = offset & 0xFF
            return (0xE << 12) | (14 << 8) | offset8
            
        elif mnemonic == 'RET':
            # RET -> JALR x0, x14
            return (0xF << 12) | (0xC << 8) | (14 << 4) | 0
            
        elif mnemonic == 'NOP':
            return 0x0000  # ADD x0, x0, x0
            
    elif inst_type == 'DIRECTIVE':
        if mnemonic == '.WORD':
            # Raw word or label address
            if len(args) < 1:
                raise ValueError(".WORD needs value")
            arg = args[0]
            # Check if it's a label
            if labels_upper and arg.upper() in labels_upper:
                return labels_upper[arg.upper()] & 0xFFFF
            return parse_operand(arg)[1]
        elif mnemonic == '.ORG':
            # Origin - handled in pass 1
            return None
            
    elif mnemonic == '.WORD':
        # Raw word
        if len(args) < 1:
            raise ValueError(".WORD needs value")
        return parse_operand(args[0])[1]
        
    elif mnemonic == '.ORG':
        # Origin - handled in pass 1
        return None
    
    return 0

def assemble(source_file, output_file):
    """Two-pass assembler"""
    global CURRENT_EQUATES
    with open(source_file, 'r') as f:
        content = f.read()
    
    # Strip /* */ block comments first (handles multi-line with DOTALL)
    content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
    # Strip // line comments
    content = re.sub(r'//.*', '', content)
    # Split into lines
    lines = content.splitlines()
    
    # Pre-pass: collect EQU/constant definitions (NAME = VALUE)
    equates = {}
    CURRENT_EQUATES = {}
    for line in lines:
        line = line.split(';')[0].strip()
        if not line:
            continue
        # Check for NAME = VALUE (equate)
        equ_match = re.match(r'(\w+)\s*=\s*(.+)', line)
        if equ_match:
            name = equ_match.group(1)
            value_str = equ_match.group(2).strip()
            # Parse value (can reference other equates)
            try:
                # Evaluate expression with current equates
                for equ_name, equ_val in equates.items():
                    value_str = value_str.replace(equ_name, str(equ_val))
                value = eval(value_str, {"__builtins__": {}}, {})
                equates[name] = value & 0xFFFF
                CURRENT_EQUATES[name] = value & 0xFFFF
            except:
                pass  # Ignore parse errors
            continue
    
    # Pass 1: collect labels
    labels = {}
    pc = 0
    for line in lines:
        line = line.split(';')[0].strip()
        if not line:
            continue
        # Skip EQU lines
        if re.match(r'\w+\s*=', line):
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
        # Skip EQU in pass 1 too
        if re.match(r'\w+\s*=', line):
            continue
        pc += 1
    
    # Pass 2: generate code
    # Create case-insensitive label lookup
    labels_upper = {k.upper(): v for k, v in labels.items()}
    pc = 0
    words = []
    for line in lines:
        line = line.split(';')[0].strip()
        if not line:
            continue
        # Skip EQU lines
        if re.match(r'\w+\s*=', line):
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
            word = assemble_line(line, pc, labels, equates, labels_upper)
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
