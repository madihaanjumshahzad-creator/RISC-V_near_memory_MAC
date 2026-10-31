# Top-level flow:  make test   -> unit tests + full-system simulation
#                  make lint   -> Verilator lint of the accelerator
CROSS   ?= riscv64-unknown-elf-
CFLAGS  = -march=rv32im_zicsr -mabi=ilp32 -O2 -ffreestanding -nostdlib -Wall
RTL     = rtl/soc_top.v rtl/mac_accel.v third_party/picorv32/picorv32.v

.PHONY: all test unit soc lint clean
all: test

build/firmware.elf: fw/start.S fw/main.c fw/link.ld
	mkdir -p build
	$(CROSS)gcc $(CFLAGS) -T fw/link.ld -o $@ fw/start.S fw/main.c

build/firmware.hex: build/firmware.elf
	$(CROSS)objcopy -O binary $< build/firmware.bin
	python3 fw/bin2hex.py build/firmware.bin $@ 16384

build/soc_sim: $(RTL) sim/tb_soc.v
	mkdir -p build
	iverilog -g2012 -o $@ -s tb_soc sim/tb_soc.v $(RTL)

soc: build/firmware.hex build/soc_sim
	vvp -n build/soc_sim

unit:
	$(MAKE) -C tests

lint:
	verilator --lint-only -Wall rtl/mac_accel.v

test: lint unit soc

clean:
	rm -rf build tests/sim_build tests/results.xml tests/__pycache__
