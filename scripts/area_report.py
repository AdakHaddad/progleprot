#!/usr/bin/env python3
"""
Parse Yosys stat output and generate area report.
Run after: yosys scripts/synth.ys 2>&1 | tee synth.log
Then: python3 scripts/area_report.py synth.log
"""

import re
import sys

def parse_yosys_log(log_file):
    """Parse Yosys stat output for cell counts."""
    blocks = {}
    current_top = None
    
    with open(log_file) as f:
        for line in f:
            # Detect hierarchy top
            m = re.search(r'hierarchy -top (\w+)', line)
            if m:
                current_top = m.group(1)
                blocks[current_top] = {'cells': 0, 'wires': 0, 'ff': 0}
            
            # Parse stat output
            if 'Number of cells:' in line:
                m = re.search(r'Number of cells:\s+(\d+)', line)
                if m and current_top:
                    blocks[current_top]['cells'] = int(m.group(1))
            
            if 'Number of wires:' in line:
                m = re.search(r'Number of wires:\s+(\d+)', line)
                if m and current_top:
                    blocks[current_top]['wires'] = int(m.group(1))
            
            if 'Number of wire bits:' in line:
                m = re.search(r'Number of wire bits:\s+(\d+)', line)
                if m and current_top:
                    blocks[current_top]['wire_bits'] = int(m.group(1))
            
            # Flip-flop count
            if '  $_DFF' in line or '  $_DFFE' in line or '  $_DFF_' in line:
                m = re.search(r'\s+(\d+)\s+\$_DFF', line)
                if m and current_top:
                    blocks[current_top]['ff'] = blocks[current_top].get('ff', 0) + int(m.group(1))
    
    return blocks

def print_report(blocks):
    print("\n=== Area Report (Yosys generic cells) ===")
    print(f"{'Module':<20} {'Cells':>8} {'Wires':>8} {'WireBits':>10} {'FFs':>8}")
    print("-" * 60)
    
    total_cells = 0
    total_ff = 0
    
    for name in ['m1_top', 'm2_top', 'm3_top', 'm4_top', 'm5_top', 'm6_top']:
        if name in blocks:
            b = blocks[name]
            print(f"{name:<20} {b['cells']:>8} {b['wires']:>8} {b.get('wire_bits',0):>10} {b.get('ff',0):>8}")
            total_cells += b['cells']
            total_ff += b.get('ff', 0)
    
    print("-" * 60)
    print(f"{'TOTAL (m6_top)':<20} {total_cells:>8} {'':>8} {'':>10} {total_ff:>8}")
    print(f"\nBudget: ~32K cells (IHP 8x4 tiles)")
    print(f"Margin: {32000 - total_cells:>5} cells ({100*(32000-total_cells)/32000:.1f}%)")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python3 area_report.py <synth.log>")
        sys.exit(1)
    blocks = parse_yosys_log(sys.argv[1])
    print_report(blocks)
