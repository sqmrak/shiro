import struct

ARMV7 = (12, 9)
ARM64 = (0x100000c, 0)
ARM64E = (0x100000c, 2)
EXECUTABLE_TARGETS = {ARMV7: 0x50000, ARM64: 0x70000, ARM64E: 0xe0000}


def verify_macho(binary, targets, signed=True):
    assert binary[:4] == b'\xca\xfe\xba\xbe', 'expected a universal Mach-O'
    count = struct.unpack_from('>I', binary, 4)[0]
    assert count == len(targets), count
    architectures = set()
    for index in range(count):
        cpu, subtype, offset, size, align = struct.unpack_from('>IIIII', binary, 8 + index * 20)
        architecture = (cpu, subtype & 0x00ffffff)
        assert architecture in targets and architecture not in architectures, architecture
        architectures.add(architecture)
        assert offset >= 8 + count * 20 and offset + size <= len(binary)
        assert struct.unpack_from('<II', binary, offset + 4) == (cpu, subtype)
        magic = struct.unpack_from('<I', binary, offset)[0]
        assert magic in (0xfeedface, 0xfeedfacf)
        header = 32 if magic == 0xfeedfacf else 28
        commands = struct.unpack_from('<I', binary, offset + 16)[0]
        pos = offset + header
        signature = False
        minimum = None
        for _ in range(commands):
            cmd, length = struct.unpack_from('<II', binary, pos)
            assert length >= 8 and pos + length <= offset + size
            if cmd == 0x1d:
                sig_offset, sig_size = struct.unpack_from('<II', binary, pos + 8)
                assert sig_size > 0 and sig_offset + sig_size <= size
                signature = True
            if cmd == 0x25:
                minimum = struct.unpack_from('<I', binary, pos + 8)[0]
            if cmd == 0x32:
                minimum = struct.unpack_from('<I', binary, pos + 12)[0]
            pos += length
        if signed:
            assert signature, 'missing code signature'
        assert minimum == targets[architecture], (architecture, minimum)
        if architecture == ARM64E:
            assert subtype >> 24 == (0x80 if minimum >= 0xe0000 else 0x00), hex(subtype)
    assert architectures == set(targets)
