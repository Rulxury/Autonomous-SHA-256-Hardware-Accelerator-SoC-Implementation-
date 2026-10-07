# Autonomous SHA-256 Hardware Accelerator — Simulation Guide

Dokumen ini berisi panduan lengkap untuk menjalankan simulasi verifikasi RTL (Unit Test, Core Integration Test, dan Equivalence Test) menggunakan **ModelSim / QuestaSim** maupun **AMD Vivado (xsim)**.

---

## 📁 Struktur Direktori

```text
quartus_sha256_soc/
├── rtl/                    # Modul-modul RTL SHA-256 (.v, .vh)
│   ├── sha256_defs.vh      # Defisit & Macro SHA-256 (ROTR, SIG0/1, BSIG0/1)
│   ├── hash_adder.v        # Hash Accumulator (Davies-Meyer 8-lane adder)
│   ├── hram.v              # Register Hash Digest 256-bit
│   ├── k_rom.v             # ROM 64 Konstanta SHA-256
│   ├── mc.v                # Compression Core Engine
│   ├── me.v                # Message Expansion (Sigma Scheduler)
│   ├── pad_fn.v            # Hardware Auto-Padding Unit
│   ├── wram.v              # Shift Register Working Word (16x32-bit)
│   ├── sha256_fsm.v        # FSM Controller State Machine
│   ├── sha256_core.v       # Top-level Core Integrator
│   ├── sha256_csr.v        # Register Interface CSR (MMIO)
│   └── sha256_accelerator.v# Top-level Hardware Accelerator
│
├── baseline/               # Baseline reference dari Open-Source SHA-256 (tt07-sha256)
│   └── project.v           # Original baseline implementation (TinyTapeout 07)
│
└── tb/                     # Suite Testbench SystemVerilog (.sv) & Script Simulasi
    ├── tb_unit_k_rom.sv        # Unit test: k_rom.v
    ├── tb_unit_wram.sv         # Unit test: wram.v
    ├── tb_unit_me.sv           # Unit test: me.v
    ├── tb_unit_hash_adder.sv   # Unit test: hash_adder.v
    ├── tb_unit_hram.sv         # Unit test: hram.v
    ├── tb_unit_pad_fn.sv       # Unit test: pad_fn.v
    ├── tb_unit_mc.sv           # Unit test: mc.v
    ├── tb_unit_sha256_fsm.sv   # Unit test: sha256_fsm.v
    ├── tb_core_raw.sv          # Integration test: Mode 0 (Raw Block, tanpa auto-pad)
    ├── tb_core_autopad.sv      # Integration test: Mode 1 (Hardware Auto-Padding)
    ├── tb_baseline_equiv.sv    # Equivalence test: core mc.v vs baseline project.v
    ├── run_vivado_sim.ps1      # Automated PowerShell runner untuk Vivado xsim
    └── run_unit_tests.tcl      # Automated TCL batch script untuk Vivado
```

---

## 🧪 Daftar Testbench & Coverage

### 1. Unit Testbenches (`rtl/` Sub-modules)
| Testbench | Modul Target | Cakupan Verifikasi |
|---|---|---|
| `tb_unit_k_rom.sv` | `k_rom.v` | Verifikasi 64 konstanta SHA-256 NIST & latensi 1 siklus |
| `tb_unit_wram.sv` | `wram.v` | Host word-write, operasi shift 16-word, tap `w0`, `w1`, `w9`, `w14` |
| `tb_unit_me.sv` | `me.v` | Fungsi kombinasional $\sigma_0$, $\sigma_1$, dan kontrol `sched_en` |
| `tb_unit_hash_adder.sv` | `hash_adder.v` | Penjumlahan 8-lane 32-bit modulo $2^{32}$ (Davies-Meyer update) |
| `tb_unit_hram.sv` | `hram.v` | Async reset ke 0, write-enable (`we`), dan register hold state |
| `tb_unit_pad_fn.sv` | `pad_fn.v` | Byte masking, penyisipan byte `0x80`, serta panjang bit (64-bit length) |
| `tb_unit_mc.sv` | `mc.v` | Load state IV & eksekusi 1 compression round vs referensi NIST |
| `tb_unit_sha256_fsm.sv` | `sha256_fsm.v` | Siklus FSM: `IDLE` $\rightarrow$ `LOAD` $\rightarrow$ `PROC` (64 rounds) $\rightarrow$ `FIN` $\rightarrow$ `IDLE` |

### 2. Integration & Baseline Equivalence
| Testbench | Fungsi & Deskripsi |
|---|---|
| `tb_core_raw.sv` | Mengetes Mode 0 (Raw Block SHA-256). Pengujian vektor NIST "abc", string kosong, dan multi-block. |
| `tb_baseline_equiv.sv` | Equivalence checking antara `mc.v` vs baseline `project.v` untuk >10.000 round. |
| `tb_core_autopad.sv` | Mengetes Mode 1 (Hardware Auto-Padding) untuk berbagai variasi panjang pesan. |

---

## 🚀 Cara Menjalankan Simulasi

### 🔹 Opsi 1: Menjalankan di ModelSim / QuestaSim

#### A. Command Line Mode (CLI)

1. Buka PowerShell / Command Prompt di akar proyek:
   ```powershell
   cd C:\PERURI\quartus_sha256_soc
   ```

2. Buat library `work` (jika belum ada):
   ```bash
   vlib work
   ```

3. Compile seluruh modul RTL:
   ```bash
   vlog +incdir+rtl rtl/hash_adder.v rtl/hram.v rtl/k_rom.v rtl/mc.v rtl/me.v rtl/pad_fn.v rtl/sha256_fsm.v rtl/wram.v rtl/sha256_core.v rtl/sha256_csr.v rtl/sha256_accelerator.v
   ```

4. Compile & Jalankan Testbench yang diinginkan:

   * **Menjalankan Unit Test (Contoh: `tb_unit_sha256_fsm`):**
     ```bash
     vlog -sv +incdir+rtl tb/tb_unit_sha256_fsm.sv
     vsim -c -do "run -all; quit" tb_unit_sha256_fsm
     ```

   * **Menjalankan Integration Test Mode 0 Raw (`tb_core_raw`):**
     ```bash
     vlog -sv +incdir+rtl tb/tb_core_raw.sv
     vsim -c -do "run -all; quit" tb_core_raw
     ```

   * **Menjalankan Baseline Equivalence Test (`tb_baseline_equiv`):**
     ```bash
     vlog baseline/project.v
     vlog -sv +incdir+rtl tb/tb_baseline_equiv.sv
     vsim -c -do "run -all; quit" tb_baseline_equiv
     ```

#### B. Interactive GUI Mode (Waveform Debugging)

1. Buka ModelSim GUI:
   ```bash
   vsim tb_core_raw
   ```
2. Di dalam konsol ModelSim TCL:
   ```tcl
   add wave -r /*
   run -all
   ```

---

### 🔸 Opsi 2: Menjalankan di AMD Vivado (xsim)

#### A. Menggunakan Automated PowerShell Script (Rekomendasi)

Tersedia script PowerShell [`tb/run_vivado_sim.ps1`](tb/run_vivado_sim.ps1) yang mengotomatisasi kompilasi (`xvlog`), elaborasi (`xelab`), dan simulasi (`xsim`) untuk seluruh unit testbench.

1. Buka PowerShell di direktori proyek:
   ```powershell
   cd C:\PERURI\quartus_sha256_soc
   ```

2. Pastikan path executable Vivado sesuai (default script: `C:\AMDDesignTools\2025.2\Vivado\bin` atau sesuai versi Vivado yang terpasang pada sistem).

3. Menjalankan **seluruh unit testbench** sekaligus:
   ```powershell
   .\tb\run_vivado_sim.ps1
   ```

4. Menjalankan **satu testbench spesifik**:
   ```powershell
   .\tb\run_vivado_sim.ps1 -TbName tb_unit_pad_fn
   ```

#### B. Menggunakan Vivado TCL Batch Mode

Anda juga dapat menggunakan script TCL [`tb/run_unit_tests.tcl`](tb/run_unit_tests.tcl):

```bash
vivado -mode batch -source tb/run_unit_tests.tcl
```

#### C. Menjalankan Manual via Command Prompt Vivado (xsim)

```powershell
# 1. Compile RTL
xvlog -sv --include rtl rtl/hash_adder.v rtl/hram.v rtl/k_rom.v rtl/mc.v rtl/me.v rtl/pad_fn.v rtl/sha256_fsm.v rtl/wram.v

# 2. Compile Testbench
xvlog -sv --include rtl tb/tb_unit_k_rom.sv

# 3. Elaborate & Simulate
xelab -debug typical tb_unit_k_rom -s tb_unit_k_rom_snap
xsim tb_unit_k_rom_snap -runall
```

---

## 📌 Catatan Timing & Arsitektur

1. **Output Control FSM Registered:** Output kontrol pada `sha256_fsm.v` (seperti `load`, `hram_we`, `done_pulse`) adalah ter-register. Sinyal `load` aktif pada siklus pertama `PROC`, dan `hram_we`/`done_pulse` aktif pada siklus tepat setelah state `FIN` (saat FSM kembali ke `IDLE`).
2. **Modular Accumulator:** Register Hash (`hram.v`) memegang akumulasi digest akhir. Nilai IV SHA-256 NIST dipilin pada tahap pertama oleh multiplexer `h_base` (`first_eff ? IV : HRAM`).

---

## 📜 Lisensi
Lisensi proyek ini menggunakan **Apache-2.0** (SPDX-License-Identifier: Apache-2.0).
