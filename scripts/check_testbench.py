#!/usr/bin/env python3
"""
Verify the testbench frame matches expected frame
"""
def compute_crc15(data_bits):
    crc = 0
    poly = 0x4599
    for bit in data_bits:
        fb = ((crc >> 14) & 1) ^ bit
        crc = ((crc << 1) & 0x7FFF) | fb
        if fb:
            crc ^= poly
    return crc & 0x7FFF

def stuff_bits(bits):
    result = []
    count = 0
    last = None
    for bit in bits:
        result.append(bit)
        if bit == last:
            count += 1
        else:
            count = 1
            last = bit
        if count == 5:
            result.append(1 - bit)
            count = 0
            last = 1 - bit
    return result

# Build expected frame
frame = []

# SOF
frame.append(0)

# 11-bit ID: 0x123 = 291 = 0b00100100011 (11 bits MSB first)
id_bits = [(0x123 >> i) & 1 for i in range(10, -1, -1)]
frame.extend(id_bits)

# RTR (0 = data frame)
frame.append(0)

# IDE (0 = standard)
frame.append(0)

# r0 (reserved, dominant)
frame.append(0)

# DLC = 2 (0010)
dlc_bits = [(2 >> i) & 1 for i in range(3, -1, -1)]
frame.extend(dlc_bits)

# Data: 0xAB, 0xCD (MSB first per byte)
data = [0xAB, 0xCD]
for byte in data:
    for i in range(7, -1, -1):
        frame.append((byte >> i) & 1)

print(f"Expected unstuffed up to data ({len(frame)} bits):")
print(''.join(str(b) for b in frame))

# Compute CRC
crc_data = frame[1:]
crc = compute_crc15(crc_data)
print(f"CRC: 0x{crc:04X} ({crc:015b})")

# Add CRC
for i in range(14, -1, -1):
    frame.append((crc >> i) & 1)

# CRC delimiter (recessive)
frame.append(1)
# ACK slot
frame.append(1)
# ACK delimiter
frame.append(1)
# EOF (7 recessive)
frame.extend([1]*7)
# IFS (3 recessive)
frame.extend([1]*3)

print(f"\nFull expected unstuffed ({len(frame)} bits):")
print(''.join(str(b) for b in frame))

# Apply stuffing
stuffed = stuff_bits(frame[:-10])
stuffed.extend(frame[-10:])

print(f"\nExpected stuffed ({len(stuffed)} bits):")
print(''.join(str(b) for b in stuffed))

# Now check testbench
testbench = [
    0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 1, 1, 0, 1, 0, 1, 0, 1, 1, 1, 0, 0, 1, 1, 0, 1, 0, 1, 1, 0, 0, 1, 0, 0, 1, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1
]
print(f"\nTestbench ({len(testbench)} bits):")
print(''.join(str(b) for b in testbench))

print(f"\nMatch? {stuffed == testbench}")

# Find first difference
for i, (a, b) in enumerate(zip(stuffed, testbench)):
    if a != b:
        print(f"First diff at {i}: expected {a}, got {b}")
        break

# Check data bits specifically
print("\n--- Data bits comparison ---")
# Data starts after SOF(1) + ID(11) + RTR(1) + IDE(1) + r0(1) + DLC(4) = 19 bits
# In stuffed frame, need to find where data is
# Let's trace through destuffing to find data
destuffed = []
count = 0
prev = None
for i, bit in enumerate(stuffed):
    if count == 5:
        if bit != prev:
            count = 0
            prev = bit
            continue
    destuffed.append(bit)
    if bit == prev:
        count += 1
    else:
        count = 1
    prev = bit

print(f"Destuffed ({len(destuffed)} bits):")
print(''.join(str(b) for b in destuffed))

# Data bits in destuffed
# SOF(1) + ID(11) + RTR(1) + IDE(1) + r0(1) + DLC(4) = 19 bits before data
print(f"\nData bits in destuffed (indices 19-34):")
for i in range(19, 35):
    print(f"  [{i}] = {destuffed[i]}")

# Expected data: 0xAB = 10101011, 0xCD = 11001101
print("Expected data bits: 10101011 11001101")
