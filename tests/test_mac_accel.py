# cocotb tests for mac_accel.v
# Each result is checked against a Python dot product.

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly

CTRL = 0x00
STATUS = 0x04
LEN = 0x08
A_OFF = 0x0C
B_OFF = 0x10
RESULT = 0x14
CYCLES = 0x18
SPAD = 0x10000
SPAD_WORDS = 1024
B_START = 2048          # byte offset where B goes in most tests

BUSY, DONE, ERROR = 1, 2, 4


def signed32(v):
    v &= 0xFFFFFFFF
    if v & 0x80000000:
        v -= 1 << 32
    return v


def ref_dot(a, b):
    return signed32(sum(x * y for x, y in zip(a, b)))


def to_words(vec):
    # 4 int8 per word, little endian, pad with 0
    vec = list(vec) + [0] * (-len(vec) % 4)
    words = []
    for i in range(0, len(vec), 4):
        w = 0
        for k in range(4):
            w |= (vec[i + k] & 0xFF) << (8 * k)
        words.append(w)
    return words


class Bus:
    # drives the PicoRV32 style valid/ready bus

    def __init__(self, dut):
        self.dut = dut
        dut.bus_valid.value = 0
        dut.bus_addr.value = 0
        dut.bus_wdata.value = 0
        dut.bus_wstrb.value = 0

    async def access(self, addr, wdata=0, wstrb=0):
        dut = self.dut
        dut.bus_valid.value = 1
        dut.bus_addr.value = addr
        dut.bus_wdata.value = wdata
        dut.bus_wstrb.value = wstrb
        for _ in range(50):
            await RisingEdge(dut.clk)
            await ReadOnly()
            if dut.bus_ready.value == 1:
                data = int(dut.bus_rdata.value)
                await RisingEdge(dut.clk)
                dut.bus_valid.value = 0
                dut.bus_wstrb.value = 0
                return data
        assert False, f"no bus_ready for address {addr:#x}"

    async def write(self, addr, data, wstrb=0xF):
        await self.access(addr, data, wstrb)

    async def read(self, addr):
        return await self.access(addr)


async def reset(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    bus = Bus(dut)
    dut.resetn.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.resetn.value = 1
    await RisingEdge(dut.clk)
    return bus


async def load(bus, offset, vec):
    for i, w in enumerate(to_words(vec)):
        await bus.write(SPAD + offset + 4 * i, w)


async def start_and_wait(bus, n, a_off, b_off):
    await bus.write(LEN, n)
    await bus.write(A_OFF, a_off)
    await bus.write(B_OFF, b_off)
    await bus.write(CTRL, 1)
    for _ in range(5000):
        status = await bus.read(STATUS)
        if status & DONE:
            return status
    assert False, "accelerator did not finish"


async def hw_dot(bus, a, b, a_off=0, b_off=B_START):
    await load(bus, a_off, a)
    await load(bus, b_off, b)
    status = await start_and_wait(bus, len(a), a_off, b_off)
    assert not status & ERROR, "error flag set"
    return signed32(await bus.read(RESULT))


@cocotb.test()
async def test_known_values(dut):
    bus = await reset(dut)
    a = [1, 2, 3, 4, 5, 6, 7, 8]
    b = [8, 7, 6, 5, 4, 3, 2, 1]
    got = await hw_dot(bus, a, b)
    assert got == 120, got


@cocotb.test()
async def test_min_max_values(dut):
    bus = await reset(dut)
    cases = [
        ([-128] * 16, [-128] * 16),
        ([-128] * 16, [127] * 16),
        ([127, -1, 0, -128], [-1, 127, 99, 1]),
    ]
    for a, b in cases:
        got = await hw_dot(bus, a, b)
        assert got == ref_dot(a, b), (a, b, got)


@cocotb.test()
async def test_length_not_multiple_of_4(dut):
    bus = await reset(dut)
    # put junk in the scratchpad first, the extra lanes must not be added
    for i in range(16):
        await bus.write(SPAD + 4 * i, 0x7F7F7F7F)
        await bus.write(SPAD + B_START + 4 * i, 0x7F7F7F7F)
    for n in range(10):
        a = [random.randint(-128, 127) for _ in range(n)]
        b = [random.randint(-128, 127) for _ in range(n)]
        # only write the bytes that belong to the vector
        for i, w in enumerate(to_words(a)):
            await bus.write(SPAD + 4 * i, w, wstrb=(1 << min(4, n - 4 * i)) - 1)
        for i, w in enumerate(to_words(b)):
            await bus.write(SPAD + B_START + 4 * i, w, wstrb=(1 << min(4, n - 4 * i)) - 1)
        await start_and_wait(bus, n, 0, B_START)
        got = signed32(await bus.read(RESULT))
        assert got == ref_dot(a, b), (n, got, ref_dot(a, b))


@cocotb.test()
async def test_error_flag(dut):
    bus = await reset(dut)
    status = await start_and_wait(bus, 8, 2, B_START)
    assert status & ERROR, "A_OFF=2 is not aligned, error expected"
    status = await start_and_wait(bus, 4 * SPAD_WORDS + 4, 0, 0)
    assert status & ERROR, "LEN too big, error expected"
    # next good run should clear it
    assert await hw_dot(bus, [3, 4], [5, 6]) == 39


@cocotb.test()
async def test_scratchpad_readback(dut):
    bus = await reset(dut)
    for i in range(32):
        await bus.write(SPAD + 4 * i, 0xA5000000 | i)
    for i in range(32):
        assert await bus.read(SPAD + 4 * i) == 0xA5000000 | i


@cocotb.test()
async def test_random(dut):
    bus = await reset(dut)
    rng = random.Random(2026)
    hits = dict.fromkeys(["len=0", "len 1-3", "len not x4", "len x4", "len>=1024",
                          "neg", "pos", "zero"], 0)
    for _ in range(60):
        n = rng.choice([0, 1, 2, 3, rng.randint(4, 64), rng.randint(64, 1024),
                        rng.randint(1024, 2048)])
        a = [rng.randint(-128, 127) for _ in range(n)]
        b = [rng.randint(-128, 127) for _ in range(n)]
        got = await hw_dot(bus, a, b)
        exp = ref_dot(a, b)
        assert got == exp, (n, got, exp)

        cyc = await bus.read(CYCLES)
        assert cyc <= (n + 3) // 4 + 2, f"{cyc} cycles for n={n}"

        if n == 0:
            hits["len=0"] += 1
        elif n < 4:
            hits["len 1-3"] += 1
        elif n % 4:
            hits["len not x4"] += 1
        else:
            hits["len x4"] += 1
        if n >= 1024:
            hits["len>=1024"] += 1
        if exp < 0:
            hits["neg"] += 1
        elif exp > 0:
            hits["pos"] += 1
        else:
            hits["zero"] += 1

    dut._log.info("coverage: %s", hits)
    missing = [k for k, v in hits.items() if v == 0]
    assert not missing, f"not covered: {missing}"
