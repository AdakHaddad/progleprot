#!/usr/bin/env python3
"""
Debug the bit stuffing in detail
"""
# Unstuffed frame up to DLC (20 bits: SOF + ID + SRR + IDE + RTR + r1 + r0 + DLC)
unstuffed = [0, 0,0,1,0,0,1,0,0,1,1, 1, 0, 0, 0, 0, 0, 0, 1, 0]
print("Unstuffed (20 bits):", ''.join(str(b) for b in unstuffed))
print("Indices:")
for i, b in enumerate(unstuffed):
    print(f"  {i}: {b}")

# Apply stuffing with debug
stuffed = []
count = 0
last = None
for i, bit in enumerate(unstuffed):
    stuffed.append(bit)
    print(f"  Add bit {i}={bit}, count={count}, last={last} -> ", end="")
    if bit == last:
        count += 1
    else:
        count = 1
        last = bit
    print(f"count={count}, last={last}", end="")
    if count == 5:
        stuff_bit = 1 - bit
        stuffed.append(stuff_bit)
        print(f" -> STUFF BIT {stuff_bit} INSERTED")
        count = 0
        last = stuff_bit
    else:
        print()
print(f"Stuffed ({len(stuffed)} bits):", ''.join(str(b) for b in stuffed))
print("Stuffed indices:")
for i, b in enumerate(stuffed):
    print(f"  {i}: {b}")

# Now destuff
print("\n--- Destuffing ---")
destuffed = []
count = 0
prev = 1
for i, bit in enumerate(stuffed):
    print(f"  Bit {i}={bit}, count={count}, prev={prev} -> ", end="")
    if count == 5:
        # This should be stuff bit
        if bit != prev:
            print(f"STUFF BIT (discard), count=0")
            count = 0
            # prev unchanged
        else:
            print(f"STUFF ERROR!")
            count = 0
    else:
        destuffed.append(bit)
        if bit == prev:
            count += 1
        else:
            count = 1
        prev = bit
        print(f"DATA, count={count}, prev={prev}")
print(f"Destuffed ({len(destuffed)} bits):", ''.join(str(b) for b in destuffed))
print("Matches original?", destuffed == unstuffed)
