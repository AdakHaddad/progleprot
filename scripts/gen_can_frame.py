#!/usr/bin/env python3
"""
Generate a properly stuffed CAN frame for testing.
CAN 2.0A standard frame:
- SOF: 1 bit (dominant = 0)
- 11-bit ID (MSB first)
- RTR: 1 bit (0 = data frame)
- IDE: 1 bit (0 = standard frame)
- r0: 1 bit (reserved, dominant = 0)
- DLC: 4 bits (0-8)
- Data: DLC * 8 bits (MSB first per byte)
- CRC: 15 bits
- CRC delimiter: 1 bit (recessive = 1)
- ACK slot: 1 bit (recessive = 1, receiver drives dominant)
- ACK delimiter: 1 bit (recessive = 1)
- EOF: 7 bits (recessive = 1)
- IFS: 3 bits (recessive = 1)

Bit stuffing: after 5 consecutive bits of same polarity, insert 1 stuff bit of opposite polarity.
Stuff bits are NOT included in CRC calculation.
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

print(f"Unstuffed frame ({len(frame)} bits):")
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

print(f"\nUnstuffed frame with CRC/EOF/IFS ({len(frame)} bits):")
print(''.join(str(b) for b in frame))

# Apply bit stuffing to the entire frame (except IFS? actually stuffing applies to all bits from SOF to EOF)
# In CAN, bit stuffing applies from SOF to CRC delimiter inclusive
# EOF and IFS are not stuffed
stuffed_frame = frame[:-10]  # Exclude EOF+IFS from stuffing
stuffed_frame = stuff_bits(stuffed_frame)
stuffed_frame.extend(frame[-10:])  # Add back EOF+IFS (unstuffed)

print(f"\nStuffed frame ({len(stuffed_frame)} bits):")
print(''.join(str(b) for b in stuffed_frame))

# Generate testbench send_can_bit calls
print("\n--- Testbench send_can_bit calls ---")
for i, bit in enumerate(stuffed_frame):
    print(f"send_can_bit({bit});  // bit {i}")

print(f"\nTotal bits: {len(stuffed_frame)}")
print(f"Expected data: 0xABCD")
print(f"Expected frame_id: 0x123")
print(f"Expected DLC: 2")
print(f"Expected extended_id: 0")
print(f"Expected rtr: 0")
