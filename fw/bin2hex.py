# Turns a .bin file into a .hex file for $readmemh, one 32-bit word per line.
# usage: bin2hex.py in.bin out.hex [words]   (pads with zeros up to words)
import sys

data = open(sys.argv[1], "rb").read()
data += b"\0" * (-len(data) % 4)
with open(sys.argv[2], "w") as f:
    for i in range(0, len(data), 4):
        f.write(f"{int.from_bytes(data[i:i+4], 'little'):08x}\n")
    for _ in range(len(data) // 4, int(sys.argv[3]) if len(sys.argv) > 3 else 0):
        f.write("00000000\n")
