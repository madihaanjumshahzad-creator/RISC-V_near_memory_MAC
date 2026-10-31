# cocotb unit tests for the accelerator (Icarus Verilog)
SIM ?= icarus
TOPLEVEL_LANG = verilog
VERILOG_SOURCES = $(CURDIR)/../rtl/mac_accel.v
COCOTB_TOPLEVEL = mac_accel
COCOTB_TEST_MODULES = test_mac_accel

include $(shell cocotb-config --makefiles)/Makefile.sim
