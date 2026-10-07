// SPDX-FileCopyrightText: Copyright (c) 2026 Peruri
// SPDX-License-Identifier: Apache-2.0
//
// sha256_defs.vh — Shared definitions for SHA-256 accelerator
// Part of quartus_sha256_soc; integrates and extends baseline tt07-sha256.

`ifndef SHA256_DEFS_VH
`define SHA256_DEFS_VH

`define ROTR(x,n)  (((x) >> (n)) | ((x) << (32-(n))))
`define SIG0(x)    (`ROTR(x,7)  ^ `ROTR(x,18) ^ ((x) >> 3))     // sigma0 (message schedule)
`define SIG1(x)    (`ROTR(x,17) ^ `ROTR(x,19) ^ ((x) >> 10))    // sigma1 (message schedule)
`define BSIG0(x)   (`ROTR(x,2)  ^ `ROTR(x,13) ^ `ROTR(x,22))    // Sigma0 (compression)
`define BSIG1(x)   (`ROTR(x,6)  ^ `ROTR(x,11) ^ `ROTR(x,25))    // Sigma1 (compression)
`define NIST_IV    256'h6a09e667_bb67ae85_3c6ef372_a54ff53a_510e527f_9b05688c_1f83d9ab_5be0cd19
// Packing 256-bit: {A,B,C,D,E,F,G,H}; A = [255:224], H = [31:0]

`endif // SHA256_DEFS_VH
