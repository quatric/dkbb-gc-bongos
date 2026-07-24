import os
import subprocess

def compile_hook(src, addr):
    os.system(f"powerpc-eabi-gcc -c -mbig-endian -O2 {src} -o temp.o")
    os.system("powerpc-eabi-objcopy -O binary temp.o temp.bin")
    with open("temp.bin", "rb") as f:
        data = f.read()
    
    # Pad to multiple of 4 bytes
    if len(data) % 4 != 0:
        data += b'\x00' * (4 - (len(data) % 4))
        
    words = []
    for i in range(0, len(data), 4):
        words.append(data[i:i+4].hex().upper())
        
    # CRITICAL FIX: The Gecko C2 handler OVERWRITES the last word with the return branch!
    # So we MUST append an extra word (60000000 = nop) at the very end.
    words.append("60000000")
        
    pair_count = (len(words) + 1) // 2
    
    print(f"C2{addr[2:]} {pair_count:08X}")
    for i in range(0, len(words), 2):
        w1 = words[i]
        w2 = words[i+1] if i+1 < len(words) else "00000000"
        print(f"{w1} {w2}")

compile_hook("codeA.s", "80248090")
# compile_hook("codeB.s", "80246588")
compile_hook("codeC.s", "8024791C")
compile_hook("codeD.s", "80247500")
