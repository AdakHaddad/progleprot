#!/usr/bin/env python3
"""
Quick area estimation from Verilog - counts modules, always blocks, registers.
Run: python3 scripts/quick_area.py
"""

import os
import re

RTL_DIR = '../rtl'

def count_in_file(fpath):
    with open(fpath) as f:
        content = f.read()
    
    # Count modules
    modules = len(re.findall(r'module\s+\w+', content))
    
    # Count always blocks (sequential + combinational)
    always_seq = len(re.findall(r'always\s*@\s*\(posedge\s+clk', content))
    always_comb = len(re.findall(r'always\s*@\s*\*', content))
    
    # Count reg declarations (rough FF estimate)
    regs = len(re.findall(r'\breg\s+\[', content))
    regs_simple = len(re.findall(r'\breg\s+\w+', content))
    
    # Count case statements (FSM complexity)
    cases = len(re.findall(r'\bcase\s*\(', content))
    
    # Parameter count
    params = len(re.findall(r'parameter\s+\w+', content))
    
    return {
        'modules': modules,
        'always_seq': always_seq,
        'always_comb': always_comb,
        'regs': regs + regs_simple,
        'cases': cases,
        'params': params
    }

def main():
    print("=== Quick RTL Complexity Report ===\n")
    print(f"{'File':<30} {'Mod':>3} {'@posedge':>8} {'@*':>5} {'Regs':>5} {'Case':>5} {'Param':>5}")
    print("-" * 75)
    
    totals = {'modules':0, 'always_seq':0, 'always_comb':0, 'regs':0, 'cases':0, 'params':0}
    
    for fname in sorted(os.listdir(RTL_DIR)):
        if fname.endswith('.v'):
            fpath = os.path.join(RTL_DIR, fname)
            c = count_in_file(fpath)
            print(f"{fname:<30} {c['modules']:>3} {c['always_seq']:>8} {c['always_comb']:>5} {c['regs']:>5} {c['cases']:>5} {c['params']:>5}")
            for k in totals:
                totals[k] += c[k]
    
    print("-" * 75)
    print(f"{'TOTAL':<30} {totals['modules']:>3} {totals['always_seq']:>8} {totals['always_comb']:>5} {totals['regs']:>5} {totals['cases']:>5} {totals['params']:>5}")
    
    # Rough cell estimate: ~10 cells per always_seq, ~5 per always_comb, ~2 per reg, ~3 per case
    est_cells = (totals['always_seq'] * 10 + totals['always_comb'] * 5 + 
                 totals['regs'] * 2 + totals['cases'] * 3 + totals['modules'] * 50)
    print(f"\nRough cell estimate: ~{est_cells} generic cells")
    print(f"Budget: 32K cells -> {100*(32000-est_cells)/32000:.1f}% margin")

if __name__ == '__main__':
    main()
