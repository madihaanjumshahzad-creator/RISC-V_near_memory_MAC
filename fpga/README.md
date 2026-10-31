# FPGA (not done yet)

So far everything is tested in simulation only.

To run it on a board I still need to add:

1. A top-level wrapper for the board. It connects the board clock and a reset
   button to `soc_top`, and sends `out_char` to a UART so the output shows up
   in a serial terminal on the PC.
2. A constraints file for the clock, reset and UART pins (the board vendor
   gives one).
3. Synthesis:
   - Sipeed Tang Nano 9K (around $25): Yosys + nextpnr-himbaechel (Gowin),
     or the free Gowin EDA Education edition.
   - Digilent Basys 3 or Arty A7: AMD Vivado (free Standard edition).

The scratchpad has one write port and two read ports, so the tools should
make it from two block RAM copies. The 64 KiB RAM fits in block RAM on all
these boards.

When it runs I will add LUTs, FFs, DSPs, BRAMs and Fmax to the main README.
