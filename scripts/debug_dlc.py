#!/usr/bin/env python3
"""
Debug DLC bit position after stuffing
"""
# Unstuffed frame up to DLC
unstuffed = [0, 0,0,1,0,0,1,0,0,1,1, 1, 0, 0, 0, 0,0,1,0]
print("Unstuffed (20 bits, DLC at 15-18):", ''.join(str(b) for b in unstuffed))
for i, b in enumerate(unstuffed):
    print(f"  {i}: {b}")

# Apply stuffing with debug
stuffed = []
count = 0
last = None
for i, bit in enumerate(unstuffed):
    stuffed.append(bit)
    if bit == last:
        count += 1
    else:
        count = 1
        last = bit
    if count == 5:
        stuff_bit = 1 - bit
        stuffed.append(stuff_bit)
        print(f"  STUFF at {i} (after 5 {bit}s): inserted {stuff_bit}")
        count = 0
        last = stuff_bit

print(f"\nStuffed ({len(stuffed)} bits):", ''.join(str(b) for b in stuffed))
for i, b in enumerate(stuffed):
    print(f"  {i}: {b}")

# DLC bits in unstuffed: indices 15, 16, 17, 18 = 0, 0, 1, 0
print("\nDLC bits in unstuffed (indices 15-18):", [unstuffed[i] for i in range(15, 19)])
# In stuffed, after stuff bit inserted at position 17 (0-indexed in stuffed? No, stuff inserted after unstuffed index 16)
# Stuffed index mapping:
# unstuffed 0-16 -> stuffed 0-16
# unstuffed 17 -> stuffed 18
# unstuffed 18 -> stuffed 19
print("DLC bits in stuffed (indices 17-20):", [stuffed[i] for i in range(17, 21)])

# Let's also check the full frame DLC position
full_unstuffed = [0, 0,0,1,0,0,1,0,0,1,1, 1, 0, 0, 0, 0,0,1,0] + [0,1,0,1,0,1,0,1, 1,0,1,1, 1,0,0,1,1,0,1] + [0,1,1,0,1,0,0,1,0,1,1,0,0,0] + [1, 1, 1] + [1]*7 + [1]*3
print(f"\nFull unstuffed len: {len(full_unstuffed)}")

# Find DLC in full
for i in range(len(full_unstuffed)):
    if i >= 15 and i < 19:
        print(f"  DLC bit {i}: {full_unstuffed[i]}")

# Apply stuffing
stuffed_full = []
count = 0
last = None
for i, bit in enumerate(full_unstuffed):
    stuffed_full.append(bit)
    if bit == last:
        count += 1
    else:
        count = 1
        last = bit
    if count == 5:
        stuff_bit = 1 - bit
        stuffed_full.append(stuff_bit)
        count = 0
        last = stuff_bit

print(f"\nFull stuffed len: {len(stuffed_full)}")
# DLC in stuffed - need to find where it is
# Unstuffed DLC at 15-18
# Count stuff bits before DLC
stuff_before = 0
for i in range(15):
    # check if stuff bit was inserted at or before this position
    pass

# Better: track mapping
unstuffed_to_stuffed = []
stuffed_to_unstuffed = []
count = 0
last = None
for i, bit in enumerate(full_unstuffed):
    unstuffed_to_stuffed.append(len(stuffed_full))
    stuffed_full.append(bit)
    if bit == last:
        count += 1
    else:
        count = 1
        last = bit
    if count == 5:
        stuff_bit = 1 - bit
        stuffed_full.append(stuff_bit)
        count = 0
        last = stuff_bit

# Rebuild
stuffed_full = []
count = 0
last = None
unstuffed_idx = 0
for bit in full_unstuffed:
    stuffed_full.append(bit)
    if bit == last:
        count += 1
    else:
        count = 1
        last = bit
    if count == 5:
        stuff_bit = 1 - bit
        stuffed_full.append(stuff_bit)
        count = 0
        last = stuff_bit

# Track mapping
stuffed_idx = 0
unstuffed_idx = 0
count = 0
last = None
mapping = []
for i, bit in enumerate(full_unstuffed):
    mapping.append((unstuffed_idx, stuffed_idx))
    stuffed_idx += 1
    if bit == last:
        count += 1
    else:
        count = 1
        last = bit
    if count == 5:
        # stuff bit
        stuffed_idx += 1
        count = 0
        last = 1 - bit
    unstuffed_idx += 1

print("\nUnstuffed index -> Stuffed index mapping (for DLC bits 15-18):")
for u, s in mapping:
    if 15 <= u <= 18:
        print(f"  Unstuffed[{u}] = {full_unstuffed[u]} -> Stuffed[{s}]")

print(f"\nFull stuffed bits:")
for i, b in enumerate(stuffed_full):
    if i < 30:
        print(f"  {i}: {b}")

