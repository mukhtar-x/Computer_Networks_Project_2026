import random
import struct
import unittest
import zlib

from errors.codes_h import crc32, even_parity, internet_checksum


class CodeTests(unittest.TestCase):
    def test_crc32_matches_zlib(self):
        rng = random.Random(30)
        for length in range(257):
            data = bytes(rng.getrandbits(8) for _ in range(length))
            self.assertEqual(crc32(data), zlib.crc32(data))

    def test_internet_checksum_verifies(self):
        rng = random.Random(31)
        for length in range(257):
            data = bytes(rng.getrandbits(8) for _ in range(length))
            padded = data + (b"\x00" if length & 1 else b"")
            packet = padded + struct.pack("!H", internet_checksum(data))
            self.assertEqual(internet_checksum(packet), 0)

    def test_even_parity_detects_single_bit_flip(self):
        rng = random.Random(32)
        for length in range(1, 65):
            data = bytearray(rng.getrandbits(8) for _ in range(length))
            parity = even_parity(data)
            for bit in range(length * 8):
                changed = bytearray(data)
                changed[bit // 8] ^= 1 << (bit % 8)
                self.assertNotEqual(even_parity(changed), parity)


if __name__ == "__main__":
    unittest.main()
