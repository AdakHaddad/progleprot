#!/usr/bin/env python3
"""
Debug the bit stuffing in the testbench frame
"""
# Unstuffed frame up to DLC (19 bits)
unstuffed = [0, 0,0,1,0,0,1,0,0,1,1, 0, 0, 0, 0,0,1,0]
print("Unstuffed (19 bits):", ''.join(str(b) for b in unstuffed))

# Apply stuffing
stuffed = []
count = 0
last = None
for bit in unstuffed:
    stuffed.append(bit)
    if bit == last:
        count += 1
    else:
        count = 1
        last = bit
    if count == 5:
        # Insert stuff bit (opposite polarity)
        stuffed.append(1 - bit)
        count = 0
        last = 1 - bit
        print(f"  Stuff bit inserted after position {len(stuffed)-2}: {1-bit}")

print(f"Stuffed ({len(stuffed)} bits):", ''.join(str(b) for b in stuffed))

# Now let's see what the detector would see for DLC
# DLC starts at bit 15 in unstuffed (0-indexed: bits 15,16,17,18 = 0,0,1,0)
# In stuffed, we need to find where DLC bits are
print("\nDLC bits in unstuffed (indices 15-18):", unstuffed[15:19])
print("DLC bits in stuffed (need to find):")
# The stuff bit was inserted after 5 zeros at positions 10-14 (0-indexed in unstuffed)
# So in stuffed, DLC starts at index 15+1 = 16
print("Stuffed indices 16-19:", stuffed[16:20])
