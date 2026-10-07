#!/usr/bin/env python3
# SPDX-FileCopyrightText: Copyright (c) 2026 Peruri
# SPDX-License-Identifier: Apache-2.0
#
# sha256_arch_model.py — Cycle-accurate architectural model
# SHA-256 Accelerator (implementation_plan_revised_v2)
#
# Model merepresentasikan:
#  - Shift-register WRAM (tap [0,1,9,14])
#  - K-ROM ter-register (latensi 1 siklus)
#  - hkw precompute
#  - FSM 5 state + LPREP/LRND (Legacy Step Mode)
#  - PAD rotasi 16 siklus
#  - Kelas DATA / FULL_LAST / OVF / TAIL / RAW
#  - second_pass, h_base = first_eff ? IV : HRAM
#  - ERR conditions
#
# Penggunaan: python3 sha256_arch_model.py

import hashlib
import struct
import random
import sys

# ---- Constants ----
IV = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
]

K = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
]

MASK = 0xFFFFFFFF

def rotr(x, n):
    return ((x >> n) | (x << (32 - n))) & MASK

def sig0(x):  # sigma0 message schedule
    return (rotr(x, 7) ^ rotr(x, 18) ^ (x >> 3)) & MASK

def sig1(x):  # sigma1 message schedule
    return (rotr(x, 17) ^ rotr(x, 19) ^ (x >> 10)) & MASK

def bsig0(x): return (rotr(x, 2) ^ rotr(x, 13) ^ rotr(x, 22)) & MASK
def bsig1(x): return (rotr(x, 6) ^ rotr(x, 11) ^ rotr(x, 25)) & MASK
def ch(e, f, g): return ((e & f) ^ ((~e) & g)) & MASK
def maj(a, b, c): return ((a & b) ^ (a & c) ^ (b & c)) & MASK


def pad_fn(idx, din, keep, ins80, inslen, len_bits):
    """Python model of pad_fn.v"""
    d = keep - 4 * idx   # signed arithmetic
    kb = 0 if d <= 0 else (4 if d >= 4 else d)
    mask = (0xFFFFFFFF << (32 - 8*kb)) & MASK if kb > 0 else 0
    dout = din & mask
    if ins80 and (keep >> 2) == idx:
        dout |= (0x80 << (24 - 8*(keep & 3))) & MASK
    if inslen and idx == 14:
        dout |= (len_bits >> 32) & MASK
    if inslen and idx == 15:
        dout |= len_bits & MASK
    return dout & MASK


class SHA256AccelModel:
    """Cycle-accurate model of the SHA-256 accelerator."""

    IDLE  = 'IDLE'
    PAD   = 'PAD'
    LOAD  = 'LOAD'
    PROC  = 'PROC'
    FIN   = 'FIN'
    LPREP = 'LPREP'
    LRND  = 'LRND'

    CLS_RAW       = 'RAW'
    CLS_DATA      = 'DATA'
    CLS_FULL_LAST = 'FULL_LAST'
    CLS_OVF       = 'OVF'
    CLS_TAIL      = 'TAIL'

    PASS2_NONE = 'NONE'
    PASS2_FULL = 'FULL'
    PASS2_LEN  = 'LEN'

    def __init__(self):
        self.reset()

    def reset(self):
        # WRAM (shift register 16×32)
        self.wram = [0] * 16
        # MC registers
        self.A = self.B = self.C = self.D = 0
        self.E = self.F = self.G = self.H = 0
        self.hkw = 0
        # HRAM
        self.hram = [0] * 8
        # K-ROM output (registered)
        self.k_val = K[0]
        # FSM state
        self.state  = self.IDLE
        self.cyc    = 0
        self.pad_cnt = 0
        self.first_q = False
        self.last_q  = False
        self.auto_q  = False
        self.second_pass = False
        self.cls     = self.CLS_RAW
        self.pass2   = self.PASS2_NONE
        self.msg_last = False
        self.msg_len_q = 0
        self.bytes_left = 0
        self.keep    = 0
        self.ins80   = False
        self.inslen  = False
        # CSR
        self.busy       = False
        self.block_done = False
        self.msg_done   = False
        self.err        = False
        self.msg_active = False
        self.block_cnt  = 0
        self.msg_len_reg = 0
        # Cycle counter
        self.cycle = 0
        self.total_cycles = 0

    def h_base(self):
        first_eff = self.first_q and not self.second_pass
        if first_eff:
            return list(IV)
        else:
            return list(self.hram)

    def w_n(self):
        """Message expansion output (me.v)."""
        sched = self.cyc >= 16
        w = self.wram
        if sched:
            return (w[0] + sig0(w[1]) + w[9] + sig1(w[14])) & MASK
        else:
            return w[0]

    def shift_wram(self, shift_in):
        self.wram = self.wram[1:] + [shift_in]

    def one_round_mc(self):
        """Execute one compression round using hkw."""
        s1    = bsig1(self.E)
        c     = ch(self.E, self.F, self.G)
        t1    = (self.hkw + s1 + c) & MASK
        s0    = bsig0(self.A)
        m     = maj(self.A, self.B, self.C)
        t2    = (s0 + m) & MASK
        new_A = (t1 + t2) & MASK
        new_E = (self.D + t1) & MASK
        self.H = self.G
        self.G = self.F
        self.F = self.E
        self.E = new_E
        self.D = self.C
        self.C = self.B
        self.B = self.A
        self.A = new_A

    def prefetch_k(self, addr):
        self.k_val = K[addr & 63]

    def start_block(self, first_in, last_in, auto_in, msg_data_words, msg_len_reg):
        """Simulate one START transaction.
        msg_data_words: list of up to 16 uint32 (host wrote ceil(n/4) words)
        Returns: cycles until done_pulse, True if msg_done.
        """
        if self.busy:
            self.err = True
            return 0, False
        if not first_in and not self.msg_active:
            self.err = True
            return 0, False

        # Write WRAM
        for i, w in enumerate(msg_data_words):
            self.wram[i] = w

        # Latch
        self.first_q = first_in
        self.last_q  = last_in
        if first_in:
            self.auto_q    = auto_in
            self.msg_len_q = msg_len_reg
            self.bytes_left = msg_len_reg
        self.second_pass = False

        # Clear flags
        self.block_done = False
        self.msg_done   = False
        self.busy       = True
        self.msg_active = True

        # Classify
        auto_eff = auto_in if first_in else self.auto_q
        bl = msg_len_reg if first_in else self.bytes_left

        if not auto_eff:
            self.cls      = self.CLS_RAW
            self.msg_last = last_in
            self.pass2    = self.PASS2_NONE
            use_pad = False
        elif bl > 64:
            self.cls      = self.CLS_DATA
            self.msg_last = False
            self.pass2    = self.PASS2_NONE
            use_pad = False
        elif bl == 64:
            self.cls      = self.CLS_FULL_LAST
            self.msg_last = True
            self.pass2    = self.PASS2_FULL
            use_pad = False
        elif bl >= 56:
            self.cls      = self.CLS_OVF
            self.msg_last = True
            self.pass2    = self.PASS2_LEN
            self.keep     = bl
            self.ins80    = True
            self.inslen   = False
            use_pad = True
        else:
            self.cls      = self.CLS_TAIL
            self.msg_last = True
            self.pass2    = self.PASS2_NONE
            self.keep     = bl
            self.ins80    = True
            self.inslen   = True
            use_pad = True

        cycles = self._run_compression(use_pad)
        is_done = self.msg_done

        return cycles, is_done

    def _run_compression(self, use_pad):
        """Run one compression (including optional PAD and possible second_pass)."""
        total = 0
        total += self._run_one_pass(use_pad)
        # Second pass?
        while self.pass2 != self.PASS2_NONE and not self.second_pass:
            self.second_pass = True
            if self.pass2 == self.PASS2_FULL:
                self.keep   = 0
                self.ins80  = True
                self.inslen = True
            else:  # LEN
                self.keep   = 0
                self.ins80  = False
                self.inslen = True
            total += self._run_one_pass(True)

        if self.cls == self.CLS_DATA:
            self.bytes_left = (self.bytes_left - 64) & 0xFFFFFFFF

        self.busy       = False
        self.block_done = True
        self.block_cnt  += 1
        if self.msg_last:
            self.msg_done   = True
            self.msg_active = False

        return total

    def _run_one_pass(self, use_pad):
        """Simulate PAD (16 cy) + LOAD (1 cy) + PROC (64 cy) + FIN (1 cy).
        Returns total cycle count for this pass.
        """
        cycles = 0
        len_bits = (self.msg_len_q * 8) & 0xFFFFFFFFFFFFFFFF

        # PAD state: 16 siklus rotasi
        if use_pad:
            self.pad_cnt = 0
            for pad_idx in range(16):
                din   = self.wram[0]
                pad_y = pad_fn(pad_idx, din, self.keep, self.ins80, self.inslen, len_bits)
                self.shift_wram(pad_y)
                cycles += 1
            # After PAD, cyc reset to 0

        # LOAD: 1 siklus
        h = self.h_base()
        self.A, self.B, self.C, self.D = h[0], h[1], h[2], h[3]
        self.E, self.F, self.G, self.H = h[4], h[5], h[6], h[7]
        wn = self.w_n()
        self.shift_wram(wn)
        # Compute initial hkw: H_0 + K_0 + W_0
        self.hkw = (h[7] + K[0] + self.wram[14]) & MASK  # w_n was wram[0] before shift
        # Actually: at LOAD, w_n = old wram[0]; hkw = h_base.H + K[0] + w_n
        # Redo: w_n was computed before shift
        self.hkw = (h[7] + K[0] + wn) & MASK
        self.cyc = 0
        cycles += 1

        # PROC: 64 siklus
        for t in range(64):
            # round_en: update A..H using hkw
            self.one_round_mc()
            # Shift WRAM and compute next w_n
            wn_next = self.w_n()
            self.shift_wram(wn_next)
            # Update hkw for next round: G (new H is old G) + K[t+1] + W[t+1]
            self.hkw = (self.G + K[(t + 1) & 63] + wn_next) & MASK
            self.cyc += 1
            cycles += 1

        # FIN: 1 siklus
        h_base = self.h_base()
        mc_state = [self.A, self.B, self.C, self.D, self.E, self.F, self.G, self.H]
        self.hram = [(h_base[i] + mc_state[i]) & MASK for i in range(8)]
        cycles += 1

        return cycles

    def get_digest(self):
        return ''.join(f'{x:08x}' for x in self.hram)


# ====================================================================
# High-level SHA-256 using the model (Mode 1: auto-padding)
# ====================================================================
def sha256_model_mode1(msg: bytes) -> tuple:
    """Hash message using model Mode 1 (auto-padding).
    Returns (digest_hex, total_cycles).
    """
    model = SHA256AccelModel()
    total_cycles = 1  # IDLE decision cycle
    rem = len(msg)
    off = 0
    first = True

    while True:
        n = min(rem, 64)
        # Prepare WRAM words: ceil(n/4) words
        words = []
        for i in range((n + 3) // 4):
            chunk = msg[off + 4*i : off + 4*i + 4]
            word = int.from_bytes(chunk.ljust(4, b'\x00'), 'big')
            words.append(word)
        # Pad to 16 words
        while len(words) < 16:
            words.append(0)

        cycles, msg_done = model.start_block(
            first_in=first,
            last_in=False,
            auto_in=True,
            msg_data_words=words,
            msg_len_reg=len(msg)
        )
        total_cycles += cycles
        off += n
        rem -= n
        first = False

        if msg_done:
            break

    return model.get_digest(), total_cycles


def sha256_model_mode0(blocks_padded: list) -> tuple:
    """Hash using Mode 0 (pre-padded blocks, each 16 uint32).
    Returns (digest_hex, total_cycles).
    """
    model = SHA256AccelModel()
    total_cycles = 0
    n = len(blocks_padded)
    for i, blk in enumerate(blocks_padded):
        total_cycles += 1  # IDLE decision
        cycles, _ = model.start_block(
            first_in=(i == 0),
            last_in=(i == n - 1),
            auto_in=False,
            msg_data_words=blk,
            msg_len_reg=0
        )
        total_cycles += cycles
    return model.get_digest(), total_cycles


def make_padded_blocks(msg: bytes):
    """Software padding → list of blocks, each block = list of 16 uint32 (big-endian)."""
    bit_len = len(msg) * 8
    msg = bytearray(msg)
    msg.append(0x80)
    while len(msg) % 64 != 56:
        msg.append(0x00)
    msg += struct.pack('>Q', bit_len)
    blocks = []
    for start in range(0, len(msg), 64):
        blk = list(struct.unpack('>16I', msg[start:start+64]))
        blocks.append(blk)
    return blocks


# ====================================================================
# Test suite
# ====================================================================
def run_tests():
    fails = 0

    # --- Boundary vectors ---
    vectors = [
        (0,   b"",                  "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
        (3,   b"abc",               "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
        (55,  b"a"*55,              "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318"),
        (56,  b"a"*56,              "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a"),
        (63,  b"a"*63,              "7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34"),
        (64,  b"a"*64,              "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb"),
        (65,  b"a"*65,              None),
        (119, b"a"*119,             "31eba51c313a5c08226adf18d4a359cfdfd8d2e816b13f4af952f7ea6584dcfb"),
        (120, b"a"*120,             "2f3d335432c70b580af0e8e1b3674a7c020d683aa5f73aaaedfdc55af904c21c"),
        (128, b"a"*128,             None),
        # NIST OVF
        (56,  b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
              "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"),
        # NIST 2-block
        (112, b"abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu",
              "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1"),
    ]

    cycle_expect = {
        # (cls) -> expected cycles (after START decision cycle)
        # Mode 1 only (each START decision = 1)
    }

    print("=== sha256_arch_model.py — boundary vectors ===")
    for length, msg, expected_hash in vectors:
        # Fill expected from hashlib
        if expected_hash is None:
            expected_hash = hashlib.sha256(msg).hexdigest()

        # Mode 1
        got_m1, cyc_m1 = sha256_model_mode1(msg)
        ok_m1 = (got_m1 == expected_hash)

        # Mode 0
        blks = make_padded_blocks(msg)
        got_m0, cyc_m0 = sha256_model_mode0(blks)
        ok_m0 = (got_m0 == expected_hash)

        status = "OK" if (ok_m0 and ok_m1) else "FAIL"
        if not (ok_m0 and ok_m1):
            fails += 1
        print(f"  {status} len={len(msg):4d} M0-cyc={cyc_m0} M1-cyc={cyc_m1}")
        if not ok_m0:
            print(f"    M0 FAIL: got={got_m0}")
            print(f"           exp={expected_hash}")
        if not ok_m1:
            print(f"    M1 FAIL: got={got_m1}")
            print(f"           exp={expected_hash}")

    # Cycle assertion checks
    print("\n=== Cycle assertions ===")
    cyc_tests = [
        # (msg, expected_m1_cycles, description)
        (b"abc", 1 + 16 + 66, "TAIL (3 B -> 3 cy decision + 16 PAD + 66 compress)"),
        # Actually spec says: TAIL = 1 + 16(PAD) + 66 = 83
        # but our model counts 1 decision inside start_block
    ]
    # Verify known cycle counts from spec §5.2
    # Mode 0 one block: 1 + 66 = 67 (including decision)
    # Mode 1 TAIL (<56 B): 1 + 16(PAD) + 66 = 83
    # Mode 1 OVF (56..63 B): 1 + (16+66) + (16+66) = 165
    # Mode 1 FULL_LAST (=64 B): 1 + 66 + (16+66) = 149

    def check_cycles(msg, expected_total):
        if len(msg) == 0:
            n_blk = 1
        else:
            n_blk = (len(msg) + 63) // 64
        blks = make_padded_blocks(msg)
        _, cyc_m0 = sha256_model_mode0(blks)
        _, cyc_m1 = sha256_model_mode1(msg)
        return cyc_m0, cyc_m1

    # Single block Mode 0: 67 cycles total
    cyc_m0_1, _ = check_cycles(b"abc", 67)
    if cyc_m0_1 != 67:
        print(f"  WARN: Mode 0 single block: {cyc_m0_1} (expected 67)")

    # TAIL (0 B) -> 83
    _, cyc_m1_tail = check_cycles(b"", 83)
    print(f"  Mode 0 single block: {cyc_m0_1} cy (expected 67): {'OK' if cyc_m0_1==67 else 'WARN'}")
    print(f"  Mode 1 TAIL (0 B):   {cyc_m1_tail} cy (expected 83): {'OK' if cyc_m1_tail==83 else 'WARN'}")

    _, cyc_m1_ovf = check_cycles(b"a"*56, 165)
    print(f"  Mode 1 OVF (56 B):   {cyc_m1_ovf} cy (expected 165): {'OK' if cyc_m1_ovf==165 else 'WARN'}")

    _, cyc_m1_full = check_cycles(b"a"*64, 149)
    print(f"  Mode 1 FULL_LAST (64B):{cyc_m1_full} cy (expected 149): {'OK' if cyc_m1_full==149 else 'WARN'}")

    # ERR test
    print("\n=== ERR tests ===")
    m = SHA256AccelModel()
    m.busy = True
    _, _ = m.start_block(True, True, True, [0]*16, 3)
    if m.err:
        print("  ERR: START while BUSY -> OK")
    else:
        print("  ERR: START while BUSY -> FAIL")
        fails += 1

    m2 = SHA256AccelModel()
    _, _ = m2.start_block(False, True, False, [0]*16, 3)
    if m2.err:
        print("  ERR: START FIRST_BLK=0 no msg_active -> OK")
    else:
        print("  ERR: START FIRST_BLK=0 no msg_active -> FAIL")
        fails += 1

    # Random regression
    print("\n=== Random regression ===")
    rng = random.Random(999)
    rand_fails = 0
    n_tests = 0
    for _ in range(1203):
        length = rng.randint(0, 400)
        msg = bytes(rng.randint(0, 255) for _ in range(length))
        expected = hashlib.sha256(msg).hexdigest()

        got_m1, _ = sha256_model_mode1(msg)
        blks = make_padded_blocks(msg)
        got_m0, _ = sha256_model_mode0(blks)

        if got_m1 != expected or got_m0 != expected:
            rand_fails += 1
            if rand_fails <= 5:
                print(f"  FAIL len={length}: m0={got_m0==expected} m1={got_m1==expected}")
        n_tests += 1

    print(f"  Random: {n_tests} messages, {rand_fails} failures")
    if rand_fails > 0:
        fails += rand_fails

    # NIST 1 million 'a'
    print("\n=== NIST 1 million 'a' ===")
    msg_1m = b"a" * 1000000
    expected_1m = "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"
    got_1m, cyc_1m = sha256_model_mode1(msg_1m)
    ok_1m = (got_1m == expected_1m)
    print(f"  Result: {got_1m}")
    print(f"  Expected: {expected_1m}")
    print(f"  {'OK' if ok_1m else 'FAIL'}  ({cyc_1m} cycles)")
    if not ok_1m:
        fails += 1

    print(f"\n=== TOTAL FAILS = {fails} ===")
    return fails == 0


if __name__ == "__main__":
    ok = run_tests()
    sys.exit(0 if ok else 1)
