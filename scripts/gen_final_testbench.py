#!/usr/bin/env python3
"""
Generate final correct testbench
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

print(f"\nFull expected unstuffed ({len(frame)} bits):")
print(''.join(str(b) for b in frame))

# Apply stuffing to frame from SOF to CRC delimiter
stuffed = stuff_bits(frame[:-10])
stuffed.extend(frame[-10:])

print(f"\nExpected stuffed ({len(stuffed)} bits):")
print(''.join(str(b) for b in stuffed))

# Generate testbench
print("\n--- Testbench send_can_bit calls ---")
for i, bit in enumerate(stuffed):
    print(f"send_can_bit({bit});  // bit {i}")

print(f"\nTotal bits: {len(stuffed)}")
