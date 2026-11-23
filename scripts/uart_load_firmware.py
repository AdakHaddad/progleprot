#!/usr/bin/env python3
"""
UART Firmware Loader for Protocol Emulator on Basys3
Loads assembled firmware via USB-UART (115200 baud)
"""

import argparse
import serial
import time
import sys

def load_firmware(port, firmware_file, baudrate=115200):
    """Load firmware binary via UART protocol"""
    
    # Read firmware binary
    with open(firmware_file, 'rb') as f:
        firmware = f.read()
    
    # Pad to 16-bit words
    if len(firmware) % 2 != 0:
        firmware += b'\x00'
    
    words = []
    for i in range(0, len(firmware), 2):
        word = (firmware[i] << 8) | firmware[i+1]
        words.append(word)
    
    print(f"Loaded {len(words)} words ({len(firmware)} bytes) from {firmware_file}")
    
    # Open serial port
    ser = serial.Serial(port, baudrate, timeout=1)
    time.sleep(0.5)  # Allow connection to settle
    
    # Clear buffers
    ser.reset_input_buffer()
    ser.reset_output_buffer()
    
    # Send each word: CMD=0x01, ADDR_H, ADDR_L, DATA_H, DATA_L
    for addr, word in enumerate(words):
        cmd = bytes([
            0x01,                    # CMD: Write RAM
            (addr >> 8) & 0xFF,     # ADDR_H
            addr & 0xFF,            # ADDR_L
            (word >> 8) & 0xFF,     # DATA_H
            word & 0xFF             # DATA_L
        ])
        ser.write(cmd)
        
        # Small delay between commands
        time.sleep(0.001)
        
        if addr % 256 == 0:
            print(f"  Progress: {addr}/{len(words)} words")
    
    print(f"Sent {len(words)} words")
    
    # Send start command: CMD=0x02, LEN_H, LEN_L
    prog_len = len(words)
    start_cmd = bytes([
        0x02,                     # CMD: Start CPU
        (prog_len >> 8) & 0xFF,  # LEN_H
        prog_len & 0xFF          # LEN_L
    ])
    ser.write(start_cmd)
    print(f"Sent start command (length={prog_len})")
    
    # Wait for response
    time.sleep(0.5)
    
    # Read any response
    while ser.in_waiting:
        resp = ser.read(ser.in_waiting)
        print(f"Response: {resp.hex()}")
    
    ser.close()
    print("Done!")

def main():
    parser = argparse.ArgumentParser(description='Load firmware via UART')
    parser.add_argument('--port', required=True, help='Serial port (e.g., /dev/ttyUSB0, COM3)')
    parser.add_argument('--firmware', required=True, help='Firmware binary file')
    parser.add_argument('--baud', type=int, default=115200, help='Baud rate')
    
    args = parser.parse_args()
    
    try:
        load_firmware(args.port, args.firmware, args.baud)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
