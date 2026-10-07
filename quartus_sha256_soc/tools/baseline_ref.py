#!/usr/bin/env python3
# SPDX-FileCopyrightText: Copyright (c) 2026 Peruri
# SPDX-License-Identifier: Apache-2.0
#
# baseline_ref.py — Transkripsi round logic dari baseline/project.v ke Python
# Memvalidasi dirinya sendiri dengan menjalankan 64 round + IV lalu membandingkan hashlib.
#
# Penggunaan: python3 baseline_ref.py

import hashlib
import struct
import random

# ---- NIST IV ----
IV = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
]

# ---- K constants ----
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

# ---- Baseline round function (verbatim dari project.v) ----
# register_file[0..9] = A,B,C,D,E,F,G,H,W,K
def baseline_one_round(rf):
    """Replicate case 63 dari project.v.
    rf = list [A, B, C, D, E, F, G, H, W, K] (index 0..9)
    Returns new rf setelah satu round.
    """
    A, B, C, D, E, F, G, H, W, Kc = rf

    # s1 = Sigma1(E) — verbatim dari project.v bit slice
    s1 = (rotr(E, 6) ^ rotr(E, 11) ^ rotr(E, 25)) & MASK
    ch = ((E & F) ^ ((~E) & G)) & MASK
    temp1 = (H + s1 + ch + Kc + W) & MASK

    # s0 = Sigma0(A)
    s0  = (rotr(A, 2) ^ rotr(A, 13) ^ rotr(A, 22)) & MASK
    maj = ((A & B) ^ (A & C) ^ (B & C)) & MASK
    temp2 = (s0 + maj) & MASK

    # Update (isi case 63)
    new_A = (temp1 + temp2) & MASK
    new_B = A
    new_C = B
    new_D = C
    new_E = (D + temp1) & MASK
    new_F = E
    new_G = F
    new_H = G

    return [new_A, new_B, new_C, new_D, new_E, new_F, new_G, new_H, W, Kc]


def baseline_compress_block(h_init, W16):
    """Kompresi satu blok 512-bit menggunakan baseline round function.
    h_init: list [H0..H7] (initial hash values)
    W16:    list [W0..W15] (message words, big-endian)
    Returns [H0..H7] baru.
    """
    # Message schedule
    W = list(W16)
    for i in range(16, 64):
        sig0 = (rotr(W[i-15], 7) ^ rotr(W[i-15], 18) ^ (W[i-15] >> 3)) & MASK
        sig1 = (rotr(W[i-2], 17) ^ rotr(W[i-2], 19)  ^ (W[i-2]  >> 10)) & MASK
        W.append((W[i-16] + sig0 + W[i-7] + sig1) & MASK)

    # Initialize working registers from h_init
    rf = list(h_init) + [W[0], K[0]]  # [A..H, W, K]

    # 64 rounds
    for t in range(64):
        rf[8] = W[t]    # W_reg
        rf[9] = K[t]    # K_reg
        rf = baseline_one_round(rf)

    # Add initial hash
    return [(h_init[i] + rf[i]) & MASK for i in range(8)]


def sha256_baseline(msg: bytes) -> str:
    """Full SHA-256 using baseline round function + software padding."""
    # Padding
    bit_len = len(msg) * 8
    msg = bytearray(msg)
    msg.append(0x80)
    while len(msg) % 64 != 56:
        msg.append(0x00)
    msg += struct.pack('>Q', bit_len)
    assert len(msg) % 64 == 0

    h = list(IV)
    for blk_start in range(0, len(msg), 64):
        blk = msg[blk_start:blk_start+64]
        W16 = list(struct.unpack('>16I', blk))
        h = baseline_compress_block(h, W16)

    return ''.join(f'{x:08x}' for x in h)


def self_test():
    """Cek sendiri dengan hashlib untuk beberapa vektor."""
    vectors = [
        b"",
        b"abc",
        b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
        b"a" * 55,
        b"a" * 56,
        b"a" * 63,
        b"a" * 64,
        b"a" * 119,
        b"a" * 120,
    ]

    print("baseline_ref.py — self test")
    fails = 0
    for v in vectors:
        expected = hashlib.sha256(v).hexdigest()
        got = sha256_baseline(v)
        status = "OK" if got == expected else "FAIL"
        if got != expected:
            fails += 1
            print(f"  FAIL: len={len(v)}")
            print(f"    expected: {expected}")
            print(f"    got:      {got}")
        else:
            print(f"  OK  len={len(v):4d}: {got}")

    # Random test
    rng = random.Random(12345)
    for _ in range(200):
        length = rng.randint(0, 300)
        data = bytes(rng.randint(0, 255) for _ in range(length))
        expected = hashlib.sha256(data).hexdigest()
        got = sha256_baseline(data)
        if got != expected:
            fails += 1
            print(f"  FAIL: len={length}")

    print(f"\nbaseline_ref self-test: {fails} failures")
    return fails == 0


if __name__ == "__main__":
    ok = self_test()
    if ok:
        print("baseline_ref.py PASS — golden T1/T5 verified")
    else:
        print("baseline_ref.py FAIL")
        exit(1)
