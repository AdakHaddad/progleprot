#!/usr/bin/env python3
"""
Generate a properly stuffed CAN frame for testing.
"""

def compute_crc15(data_bits):
    """Compute CAN CRC-15 (poly 0x4599)"""
    crc = 0
    poly = 0x4599
    for bit in data_bits:
        fb = ((crc >> 14) & 1) ^ bit
        crc = ((crc << 1) & 0x7FFF) | fb
        if fb:
            crc ^= poly
    return crc & 0x7FFF

def stuff_bits(bits):
    """Apply bit stuffing: after 5 consecutive same bits, insert opposite bit"""
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
            # Insert stuff bit (opposite polarity)
            result.append(1 - bit)
            count = 0
            last = 1 - bit
    return result

# Frame: ID=0x123, DLC=2, Data=0xAB, 0xCD
# Build unstuffed frame
frame = []

# SOF
frame.append(0)

# 11-bit ID: 0x123 = 0001 0010 0011
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

print(f"Unstuffed frame up to data ({len(frame)} bits):")
print(''.join(str(b) for b in frame))

# Compute CRC on unstuffed frame (excluding SOF)
crc_data = frame[1:]  # Exclude SOF
crc = compute_crc15(crc_data)
print(f"CRC: 0x{crc:04X} ({crc:015b})")

# Add CRC (15 bits, MSB first)
for i in range(14, -1, -1):
    frame.append((crc >> i) & 1)

# CRC delimiter (recessive)
frame.append(1)

# ACK slot (recessive - transmitter sends recessive)
frame.append(1)

# ACK delimiter (recessive)
frame.append(1)

# EOF (7 recessive)
frame.extend([1]*7)

# IFS (3 recessive)
frame.extend([1]*3)

print(f"\nFull unstuffed frame ({len(frame)} bits):")
print(''.join(str(b) for b in frame))

# Apply bit stuffing to frame from SOF to CRC delimiter (bits 0 to len-10-1)
# EOF and IFS are not stuffed
stuffed_frame = stuff_bits(frame[:-10])
stuffed_frame.extend(frame[-10:])  # Add back EOF+IFS (unstuffed)

print(f"\nStuffed frame ({len(stuffed_frame)} bits):")
print(''.join(str(b) for b in stuffed_frame))

# Verify destuffing works
def destuff_bits(bits):
    result = []
    count = 0
    prev = None
    for bit in bits:
        if count == 5:
            # Should be stuff bit
            if bit != prev:
                # Valid stuff bit, discard
                count = 0
                prev = bit
                continue
            else:
                # Stuff error
                pass
        result.append(bit)
        if bit == prev:
            count += 1
        else:
            count = 1
        prev = bit
    return result

destuffed = destuff_bits(stuffed_frame)
print(f"\nDestuffed frame ({len(destuffed)} bits):")
print(''.join(str(b) for b in destuffed))
print(f"Matches original (up to EOF)? {destuffed[:-10] == frame[:-10]}")

# Generate testbench send_can_bit calls
print("\n--- Testbench send_can_bit calls ---")
for i, bit in enumerate(stuffed_frame):
    print(f"send_can_bit({bit});  // bit {i}")

print(f"\nTotal bits: {len(stuffed_frame)}")
