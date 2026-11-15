#!/usr/bin/env python3
"""
Verify the testbench frame matches expected frame bit by bit
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
frame.append(0)  # SOF
id_bits = [(0x123 >> i) & 1 for i in range(10, -1, -1)]
frame.extend(id_bits)
frame.append(0)  # RTR
frame.append(0)  # IDE
frame.append(0)  # r0
dlc_bits = [(2 >> i) & 1 for i in range(3, -1, -1)]
frame.extend(dlc_bits)
data = [0xAB, 0xCD]
for byte in data:
    for i in range(7, -1, -1):
        frame.append((byte >> i) & 1)

print(f"Expected unstuffed up to data ({len(frame)} bits):")
print(''.join(str(b) for b in frame))

crc_data = frame[1:]
crc = compute_crc15(crc_data)
for i in range(14, -1, -1):
    frame.append((crc >> i) & 1)
frame.append(1)  # CRC delimiter
frame.append(1)  # ACK slot
frame.append(1)  # ACK delimiter
frame.extend([1]*7)  # EOF
frame.extend([1]*3)  # IFS

stuffed = stuff_bits(frame[:-10])
stuffed.extend(frame[-10:])

print(f"\nExpected stuffed ({len(stuffed)} bits):")
print(''.join(str(b) for b in stuffed))

# Testbench bits
testbench = [
    0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 1, 1, 0, 1, 0, 1, 0, 1, 1, 1, 0, 0, 1, 1, 0, 1, 0, 1, 1, 0, 0, 1, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1
]
print(f"\nTestbench ({len(testbench)} bits):")
print(''.join(str(b) for b in testbench))

# Find differences
print("\nDifferences:")
for i, (a, b) in enumerate(zip(stuffed, testbench)):
    if a != b:
        print(f"  Bit {i}: expected {a}, got {b}")

# What should the data bits look like in the stuffed frame?
# Data starts after 19 unstuffed bits (SOF+ID+RTR+IDE+r0+DLC)
# With stuffing, there's a stuff bit at position 17 (0-indexed in stuffed? let's trace)

# Let's trace the exact mapping
print("\n--- Mapping unstuffed to stuffed ---")
unstuffed_to_stuffed = []
count = 0
last = None
for i, bit in enumerate(frame[:-10]):  # Only stuffed part
    unstuffed_to_stuffed.append(len(stuffed))
    if bit == last:
        count += 1
    else:
        count = 1
        last = bit
    if count == 5:
        # stuff bit will be inserted
        count = 0
        last = 1 - bit

# Rebuild
stuffed2 = []
count = 0
last = None
mapping = []
for i, bit in enumerate(frame[:-10]):
    mapping.append((i, len(stuffed2)))
    stuffed2.append(bit)
    if bit == last:
        count += 1
    else:
        count = 1
        last = bit
    if count == 5:
        stuff_bit = 1 - bit
        stuffed2.append(stuff_bit)
        count = 0
        last = stuff_bit

print("Unstuffed index -> Stuffed index (for data region):")
for u, s in mapping:
    if u >= 19 and u < 35:  # Data bits
        print(f"  Unstuffed[{u}] = {frame[u]} -> Stuffed[{s}]")

print(f"\nFull stuffed2:")
for i, b in enumerate(stuffed2):
    print(f"  {i}: {b}")

# Expected data in destuffed: indices 19-34 = 10101011 11001101
# In stuffed frame, these should appear at the mapped positions
