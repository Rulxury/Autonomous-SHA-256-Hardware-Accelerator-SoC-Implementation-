# Autonomous SHA-256 Hardware Accelerator — Engineering Implementation Specification (v2 + Integrasi Baseline tt07-sha256)

> **Target Platform:** Intel/Altera Cyclone V SoC — **DE10-Nano (`5CSEBA6U23I7`)** 
> **Baseline wajib:** `tt07-sha256` (`project.v`, modul `tt_um_xeniarose_sha256`, © 2024 xenia dragon, Apache-2.0). Proyek ini adalah **turunan (integrasi + modifikasi)** dari baseline tersebut, bukan desain dari nol: `mc.v` diturunkan dari `project.v` dan seluruh fitur v2 menggerakkan round engine baseline (§4.6, §12).  
> **Toolchain:** Intel Quartus Prime Lite, Platform Designer, ModelSim/Questa-Intel FPGA Edition (atau Verilator ≥ 5 untuk testbench)  
> **Target Fmax:** ≥ 100 MHz, single clock domain *(tercapai atau tidaknya ditentukan oleh Timing Analyzer; lihat §8.3 untuk fallback)*  
> **Estimasi Area (pra-sintesis):** ≈ 1.320 FF, ≈ 1.400–2.400 ALM (≈ 3–6% dari 41.910 ALM), **0 DSP**, **1 M10K** *(dipakai 2 kbit dari 10 kbit)*; dengan `LEGACY_EN = 0` (§12.4): ≈ 1.250 FF, ≈ 1.250–2.050 ALM  
> **Latensi Core:** **66 siklus clock per blok 512-bit** (1 LOAD + 64 round + 1 FINALIZE), +1 siklus keputusan START  
> **Fitur:** Synchronous startup, on-the-fly message expansion dengan *precompute `H+K+W`*, Auto-Padding berbasis FSM (tanpa dummy write), multi-block chaining, W1C status, IRQ, **integrasi baseline `project.v` (round engine + Legacy Step Mode, §12)**  
> **Referensi arsitektur:** iterative single-PE dengan memori terpisah (WRAM / K-ROM / HRAM), *terinspirasi* dari Tran et al., "A High-Performance Multimem SHA-256 Accelerator for Society 5.0" (IEEE Access). Desain ini **tidak** memakai pipelined ALU seperti di paper; jangan memakai angka performa paper sebagai klaim desain ini.  
> **Status validasi spesifikasi:** seluruh perilaku fungsional dan hitungan siklus di dokumen ini sudah dicocokkan dengan model Python `sha256_arch_model.py` (lihat Lampiran C). RTL, hasil Quartus, dan uji board **belum** ada. **Addendum integrasi baseline (§12) belum tercakup model tersebut**; model harus diperluas lebih dulu (§12.7). **Cakupan model belum termasuk `MSG_LEN ≥ 2²⁹` (lihat §7.2 dan Lampiran C).**

---

## 0. Ringkasan 

| # | Masalah di v1 | Perbaikan di v2 | Bagian |
|:-:|:---|:---|:-:|
| 1 | `hash_adder` memakai isi HRAM sebagai `H_old` untuk blok pertama → hash salah | `h_base = first_eff ? IV : HRAM` dipakai bersama oleh MC (load) dan `hash_adder`; `first_q` di-latch saat START | 4.7, 4.10 |
| 2 | Hash Test Vector 2 punya 65 karakter hex | Diperbaiki + vektor uji diperluas (0–120 B, NIST 112 B, 1 juta `a`) | 7.1 |
| 3 | Padding di jalur tulis WRAM: butuh dummy write, urutan register kritis, kasus `len % 64 == 0` salah | Padding dipindah ke **FSM** (state `PAD`, rotasi 16 siklus pada shift register). Host cukup menulis `ceil(n/4)` word; LAST_BLK tidak dipakai di Mode 1 | 3.5, 4.4, 4.9 |
| 4 | FSM tidak punya mekanisme overflow; 4 vs 5 state | FSM 5 state (3-bit), `second_pass`, `pass2_type`, `first_eff`; blok overflow dijalankan otomatis | 4.9 |
| 5 | BoM salah (4 DSP, 8 kbit, LE vs ALM, FF tidak dihitung) | BoM dihitung ulang dari jumlah FF; 0 DSP | 8 |
| 6 | Critical path ME + T1 + A dalam satu clock | `hkw = H+K+W` dihitung satu siklus lebih awal dan diregister; latensi tetap 66 | 4.6, 8.3 |
| 7 | Klaim throughput mengasumsikan bus ideal | Model performa terpisah (core vs bus); klaim diganti rumus + ukuran di board | 5.3 |
| 8 | IRQ tidak bisa di-acknowledge; layout STATUS salah | STATUS W1C, bit `ERR`, `ROUND[5:0]` di bits [13:8], `irq = IRQ_EN & (MSG_DONE \| ERR)` | 3.2 |
| 9 | Perilaku saat host melanggar aturan tak terdefinisi | Aturan eksplisit (tulis ke WRAM / START saat BUSY → diabaikan + `ERR`) | 3.4 |
| 10 | WRAM ambigu (LUT-RAM / FF / circular) | **Shift register 16×32 FF** dengan tap tetap `[0] [1] [9] [14]` | 4.3 |
| 11 | Modul tak punya port list; "SBO" tak terdefinisi; bahasa campur | Port list lengkap untuk semua modul, tabel K, rumus σ; referensi SBO dihapus | 4, Lamp. A |
| 12 | Antarmuka bukan Avalon-MM sesungguhnya | Sinyal Avalon standar, `readLatency = 1`, interrupt sender, panduan Platform Designer | 3.1, 10 |
| 13 *(addendum)* | v2 menyebut baseline hanya sebagai latar dan menyatakan proyek "standalone", padahal hackathon mensyaratkan integrasi dan modifikasi baseline | `mc.v` diturunkan dari `project.v`; Legacy Step Mode; testbench ekuivalensi terhadap modul baseline asli; `baseline/` tak berubah; peta turunan | 4.6, 6, 12 |

---

## 1. Project Overview & Tujuan

### 1.1. Latar Belakang
Desain dasar (`tt07-sha256`, `project.v`) hanya mengimplementasikan **satu round** SHA-256 sebagai primitif hardware. Ekspansi pesan, penjadwalan konstanta, iterasi 64 round, akumulasi hash, dan padding dikerjakan CPU lewat bus sempit 8-bit. Angka ≈ 640 siklus/blok dari v1 dapat ditelusuri ke antarmuka baseline (§12.2), tetapi harus diukur di testbench (§12.6, T2); untuk perbandingan yang adil gunakan **siklus per blok**, bukan Mhash/s pada clock yang tidak disebutkan.

**Fakta baseline** (dibaca dari `project.v`): register file 10×32 bit (`A..H, W, K`); host menulis 1 byte per transaksi; **menulis alamat 63 menjalankan satu round** dengan `temp1 = H + Σ1(E) + Ch + K + W` dalam satu siklus kombinasional. Rincian dan keanehan baseline ada di §12.2.

### 1.2. Tujuan Desain
Akselerator SHA-256 **mandiri** (memory-mapped, Avalon-MM slave) di Verilog-2001:

* **Mode 0 — Raw Block:** host menyuplai blok 512-bit yang sudah di-padding software; `LAST_BLK` menandai blok terakhir.
* **Mode 1 — Hardware Auto-Padding:** host menyuplai byte pesan mentah dan `MSG_LEN`; hardware menambahkan `0x80`, nol, dan panjang 64-bit, termasuk blok tambahan otomatis bila sisa ≥ 56 byte atau tepat 64 byte.
* **Multi-Block Chaining:** digest antar blok dipertahankan di HRAM tanpa baca-ulang oleh CPU.
* **Low-Area:** satu PE, satu buffer W (shift register), konstanta K di satu M10K.
* **Integrasi Baseline (syarat hackathon):** round engine `tt07-sha256` (`project.v`) dipakai ulang sebagai `mc.v` (diturunkan, bukan ditulis ulang). K-ROM, WRAM + ME, FSM, `hkw`, HRAM, PAD, dan CSR/Avalon menggerakkannya; fungsi asli baseline tetap tersedia lewat **Legacy Step Mode** dan dibuktikan identik dengan modul baseline asli (§12).

### 1.3. Non-Goals (v2)
Double-buffer pesan, DMA/Avalon master, SHA-224, HMAC, dan pipelining ganda **tidak** termasuk (lihat §9, Fase 5 untuk opsi).

### 1.4. Urutan Pengerjaan (disarankan)
1. **Fase 1:** `mc.v` turunan baseline (lolos `tb_baseline_equiv`, §12.6) → core Mode 0 (tanpa PAD) + test NIST. 
2. **Fase 2:** PAD/Mode 1 di FSM. 
3. **Fase 3:** CSR + Avalon + IRQ. 
4. **Fase 4:** sintesis, timing, Platform Designer, uji board. 
5. **Fase 5 (opsional):** hardening/performance.

Setiap fase punya kriteria selesai di §9.

---

## 2. Arsitektur Sistem

```text
 HPS (ARM) ── Lightweight HPS-to-FPGA bridge ── Avalon-MM ──┐          irq ──► HPS f2h_irq0
                                                            v           ^
+----------------------------------------------------------------------------------------------+
| sha256_accelerator.v (TOP)                                                                   |
|                                                                                              |
|  +--------------------+  start_req, first, last, auto, msg_len     +----------------------+  |
|  | sha256_csr.v       |------------------------------------------->|  sha256_core.v       |  |
|  |  Avalon slave      |<------------------------------------------|                      |  |
|  |  CTRL/STATUS/CNT   |  busy, blk_done_set, msg_done_set, blk_inc |  +----------------+  |  |
|  |  MSG_LEN/ID/IRQ    |                                            |  | sha256_fsm.v   |  |  |
|  |  WRAM write port --+--- host_we, host_idx, host_data ---------->|  | IDLE PAD LOAD  |  |  |
|  |  digest read   <---+--- hram_q[255:0] ---------------------------|  | PROC FIN       |  |  |
|  +--------------------+                                            |  +--------+-------+  |  |
|                                                                     |    ctrl   |          |  |
|                                                                     |           v          |  |
|     +---------+ k_addr         +-----------------------------+      |  +----------------+  |  |
|     | k_rom   |<---------------| wram (16x32 shift reg)      |      |  |                |  |  |
|     | 64x32   |                |  w[0] w[1] ... w[9] ... w[14] w[15]                  |  |  |
|     | M10K    |--k_val-----+   +--+-----+-----------+----+---+      |  |                |  |  |
|     +---------+            |      |w0   |w1,w9,w14       ^ shift_in |                |  |  |
|                            |      |     v                |         |                |  |  |
|                            |      |  +------+  w_n       |         |                |  |  |
|                            |      +->| me   |------+     |         |                |  |  |
|                            |         +------+      |     |         |                |  |  |
|          pad_fn <----------+-- w0 -----------------+-----+         |                |  |  |
|          (state==PAD)  pad_y ----------------------------^          |                |  |  |
|                            v                       v                |                |  |  |
|                      +----------------------------------+           |                |  |  |
|   h_base (256) ----->| mc.v  A..H regs + hkw register   |           |                |  |  |
|   = first_eff ? IV   |  hkw <= G + K + W_n  (1 cycle    |           |                |  |  |
|     : HRAM           |  ahead of the round that uses it)|           |                |  |  |
|                      +----------------+-----------------+           |                |  |  |
|                                       | state_out[255:0]            |                |  |  |
|   h_base ----------+                  v                             |                |  |  |
|                    +-----------> hash_adder.v --h_new--> hram.v (8x32 FF) -----------+  |  |
|                                                                                          |  |
+------------------------------------------------------------------------------------------+--+
```

> **Asal-usul `mc.v`:** kotak `mc.v` pada diagram adalah round engine dari baseline `project.v` (register `A..H`, `Σ0/Σ1/Ch/Maj`, persamaan update round). Bagian yang berubah (`hkw`, load dari `h_base`, port Legacy) dirinci di §4.6 dan §12.3. Jalur Legacy Step Mode (`leg_*` dari CSR ke `mc`, jendela baca `A..H, W, K` dari `mc` ke CSR) tidak digambar; lihat §12.4.

**Aturan aliran data per siklus** (n = indeks W yang dihitung pada siklus itu):

* `w_n = (n < 16) ? w[0] : w[0] + σ0(w[1]) + w[9] + σ1(w[14])`
* `shift_in = (state == PAD) ? pad_y : w_n`; setiap siklus `PAD`/`LOAD`/`PROC`, WRAM bergeser: `w[i] <= w[i+1]`, `w[15] <= shift_in`.
* `hkw_next = H_next + K_n + W_n` dengan `H_next = G` (register G saat ini) pada siklus PROC, atau `h_base.H` pada siklus LOAD.
* Round *t* dieksekusi pada siklus `cyc = t+1` memakai `hkw` yang diregister pada akhir siklus sebelumnya.

---

## 3. Antarmuka Host (Avalon-MM Slave)

### 3.1. Sinyal Avalon

| Sinyal | Arah | Lebar | Catatan |
|:---|:-:|:-:|:---|
| `clk` | in | 1 | Satu-satunya clock (sink clock Platform Designer) |
| `reset_n` | in | 1 | Reset sink; assert async, release sinkron (disediakan reset controller Platform Designer) |
| `avs_address` | in | 6 | **Word address** (`addressUnits = WORDS`), 64 word *(5 bit / 32 word di v2; diperlebar untuk jendela legacy, §12.4)* |
| `avs_read` | in | 1 | |
| `avs_write` | in | 1 | |
| `avs_writedata` | in | 32 | |
| `avs_readdata` | out | 32 | Ter-register, **`readLatency = 1`** (tanpa `readdatavalid`) |
| `irq` | out | 1 | Interrupt sender, level, active-high |

Tidak ada `waitrequest` (selalu 0 wait) dan tidak ada `byteenable` (hanya akses 32-bit penuh). Tidak ada `cs_n`; qualifier chip-select ditangani Platform Designer. Alamat di luar peta: baca = 0, tulis diabaikan.

### 3.2. Peta Register

| Word | Byte (offset) | Nama | Akses | Keterangan |
|:-:|:-:|:---|:-:|:---|
| `0x00` | `0x00` | `REG_CTRL` | R/W | Kontrol (bit di bawah) |
| `0x01` | `0x04` | `REG_STATUS` | R / W1C | Status (bit di bawah) |
| `0x02` | `0x08` | `REG_BLOCK_CNT` | RO | Jumlah **kompresi** sejak reset atau `SOFT_RST` terakhir (termasuk blok otomatis Mode 1) |
| `0x03` | `0x0C` | `REG_MSG_LEN` | R/W | Panjang total pesan dalam **byte** (dipakai Mode 1). **32-bit, maksimum 4 GiB − 1 byte (batas desain)**. Host wajib memeriksa `len > 0xFFFFFFFFUL` sebelum menulis register ini dan mengembalikan error bila perlu. |
| `0x04–0x13` | `0x10–0x4C` | `WRAM_DATA[0..15]` | WO | Word `W0..W15` (big-endian per word). Baca = 0 |
| `0x14–0x1B` | `0x50–0x6C` | `HRAM_DIGEST[0..7]` | RO | Digest `H0..H7` |
| `0x1C` | `0x70` | `REG_ID` | RO | `0x53484132` ("SHA2") untuk cek bring-up |
| `0x1D` | `0x74` | `REG_IRQ_MASK` | R/W | Interrupt mask (§3.2); reset ke 0 |
| `0x20–0x29` | `0x80–0xA4` | `LEG_REG[0..9]` | R/W | **Jendela legacy** (hanya bila `LEGACY_EN = 1`): `register_file[0..9]` baseline = `A,B,C,D,E,F,G,H,W,K`, word 32-bit penuh. Tulis hanya saat tidak BUSY (§12.4). `0x2A–0x3F`: baca 0, tulis diabaikan |

#### `REG_CTRL` (offset `0x00`)

| Bit | Nama | Keterangan |
|:-:|:---|:---|
| 0 | `START` | Tulis 1 untuk memulai. Self-clearing, dibaca 0. **Hanya efektif bila tidak BUSY** |
| 1 | `SOFT_RST` | Tulis 1 untuk reset lunak FSM, flag STATUS, `msg_active`, `BLOCK_CNT`. **Tidak** menghapus HRAM/WRAM. Prioritas di atas `START` pada write yang sama. Self-clearing |
| 2 | `FIRST_BLK` | 1 = blok pertama pesan (mulai dari IV). 0 = lanjutan (dari HRAM) |
| 3 | `LAST_BLK` | **Mode 0 saja:** 1 = blok terakhir → `MSG_DONE`. Diabaikan di Mode 1 |
| 4 | — | *Dihapus dari CTRL; lihat `REG_IRQ_MASK` di bawah* |
| 5 | `AUTO_PAD` | 0 = Mode 0 (raw), 1 = Mode 1 (hardware padding) |
| 6 | `LEG_STEP` | Tulis 1 menjalankan satu round baseline pada `A..H, W_reg, K_reg` (Legacy Step Mode, §12.4). Self-clearing, hanya dievaluasi pada write itu. Reserved bila `LEGACY_EN = 0` |
| 31:7 | — | Reserved (0) |

**`REG_IRQ_MASK` (offset baru `0x1D`, byte `0x74`)** — register terpisah untuk interrupt mask.

| Bit | Nama | Keterangan |
|:-:|:---|:---|
| 0 | `BLOCK_DONE_IE` | Enable `irq` pada setiap `BLOCK_DONE` (termasuk `LEG_STEP` dan blok otomatis) |
| 1 | `MSG_DONE_IE` | Enable `irq` khusus pada `MSG_DONE` |
| 2 | `ERR_IE` | Enable `irq` pada `ERR` |
| 31:3 | — | Reserved (0) |

Baca kembali nilai yang tertulis. Reset ke 0. Perubahan berlaku mulai siklus write berikutnya.

**Penting:** `FIRST_BLK`, `LAST_BLK`, dan `AUTO_PAD` hanya **dievaluasi pada write yang menyertakan `START = 1`** (diambil langsung dari `avs_writedata` pada write itu). Karena padding terjadi setelah START, tidak ada ketergantungan urutan terhadap penulisan data WRAM. Nilai `AUTO_PAD` di-latch pada blok pertama (`FIRST_BLK = 1`) dan dipakai untuk seluruh pesan; perubahan pada blok lanjutan diabaikan.

#### `REG_STATUS` (offset `0x01`)

| Bit | Nama | Akses | Keterangan |
|:-:|:---|:-:|:---|
| 0 | `BUSY` | RO | 1 mulai **siklus setelah** write START yang diterima, sampai seluruh pekerjaan selesai (termasuk PAD dan blok otomatis) |
| 1 | `BLOCK_DONE` | W1C | Pekerjaan satu START (atau satu `LEG_STEP`) selesai; WRAM boleh diisi lagi |
| 2 | `MSG_DONE` | W1C | Pesan selesai (Mode 0: `LAST_BLK`; Mode 1: blok akhir/otomatis selesai). Selalu bersamaan dengan `BLOCK_DONE` |
| 3 | `ERR` | W1C | Sticky; lihat §3.4 |
| 4 | `MSG_ACTIVE` | RO | Ada pesan berjalan (chain HRAM valid untuk blok lanjutan) |
| 7:5 | — | — | Reserved (0) |
| 13:8 | `ROUND[5:0]` | RO | Round saat ini 0–63 selama PROC, selain itu 0 |
| 31:14 | — | — | Reserved (0) |

Aturan flag:
* W1C: menulis `1` ke bit tersebut menghapusnya. Jika hardware men-set bit pada siklus yang sama, **set menang**.
* `BLOCK_DONE` dan `MSG_DONE` juga dihapus otomatis pada write START yang diterima (di siklus write itu), sehingga polling tidak membaca flag usang dari blok sebelumnya. Tidak ada mekanisme clear-on-read.
* `irq = (BLOCK_DONE_IE & BLOCK_DONE) | (MSG_DONE_IE & MSG_DONE) | (ERR_IE & ERR)`; turun setelah flag yang bersangkutan di-W1C atau `SOFT_RST`. *(Gunakan `REG_IRQ_MASK` — §3.2 — bukan bit CTRL.)*
* `LEG_STEP` menghasilkan `BLOCK_DONE`; jika `BLOCK_DONE_IE = 1` maka `irq` naik. Untuk mode polling murni, biarkan seluruh `REG_IRQ_MASK = 0`.

### 3.3. Pembacaan Digest
HRAM diperbarui **atomik 256-bit** pada siklus FINALIZE, sehingga membaca `HRAM_DIGEST` saat BUSY mengembalikan nilai lengkap sebelumnya (bukan setengah jadi), tetapi nilai itu baru berarti setelah `MSG_DONE`. Nilai tiap word adalah integer 32-bit `H_i`; mencetaknya dengan `%08x` berurutan menghasilkan string hex SHA-256 standar. Untuk membentuk array 32 byte di host little-endian, byte-swap tiap word.

**Catatan pesan dua-kompresi (OVF/FULL_LAST):** HRAM berubah **dua kali** saat BUSY: sekali di `FIN` pass-1 dan sekali di `FIN` pass-2. Setiap perubahan atomik 256-bit; `busy_q` tidak turun sampai satu siklus setelah `FIN` pass-2, jadi kedua perubahan terjadi saat BUSY masih tinggi. Hanya nilai setelah `MSG_DONE` yang valid untuk digest akhir.

### 3.4. Perilaku Pelanggaran (set `ERR`, perintah diabaikan)

| Pelanggaran | Perilaku |
|:---|:---|
| Tulis `WRAM_DATA` saat `BUSY` | Tulisan dibuang, `ERR = 1` |
| `START` saat `BUSY` | Diabaikan, `ERR = 1` |
| `START` dengan `FIRST_BLK = 0` saat `MSG_ACTIVE = 0` | Diabaikan, `ERR = 1` |
| Tulis ke register read-only / alamat tak dikenal | Diabaikan, **tanpa** `ERR` |
| `SOFT_RST` saat `BUSY` | Diizinkan; membatalkan pekerjaan |
| Tulis jendela legacy saat `BUSY` | Tulisan dibuang, `ERR = 1` |
| `LEG_STEP` saat `BUSY` | Diabaikan, `ERR = 1` |
| `START` dan `LEG_STEP` pada write yang sama | Keduanya diabaikan, `ERR = 1` |
| Baca/tulis alamat `0x2A–0x3F` | Baca 0, tulis diabaikan, **tanpa** `ERR` |

`FIRST_BLK = 1` saat `MSG_ACTIVE = 1` diizinkan (memulai pesan baru; pesan lama dibuang).

### 3.5. Protokol Host

**Endianness:** word yang ditulis ke `WRAM_DATA[i]` = 4 byte pesan dengan byte pertama di bits `[31:24]` (big-endian). Pada ARM little-endian, lakukan `__builtin_bswap32` setelah memuat 4 byte sebagai `uint32_t`. Pada word parsial terakhir di Mode 1, byte yang tidak terpakai boleh berisi apa saja (hardware me-mask).

#### Fungsi polling bersama (gunakan di semua mode)
```c
#define POLL_TIMEOUT 1000000UL
static int wait_done(void) {
    for (uint32_t t = 0; t < POLL_TIMEOUT; t++) {
        uint32_t s = REG(STATUS);
        if (s & STATUS_ERR)        return -1;   // START ditolak / pelanggaran
        if (s & STATUS_BLOCK_DONE) return 0;
    }
    return -2;                                  // timeout
}
// pemakaian: if (wait_done()) { REG(STATUS) = STATUS_ERR; REG(CTRL) = SOFT_RST; return -1; }
```

**Catatan `be32_partial`:** Salin `n % 4` byte sisa ke buffer 4 byte lokal yang diinisialisasi nol sebelum `bswap32`. Jangan membaca melewati akhir `msg`.

#### Mode 0 (AUTO_PAD = 0)
```c
// blocks = pesan yang SUDAH di-padding software (kelipatan 64 byte)
for (b = 0; b < nblocks; b++) {
    for (i = 0; i < 16; i++) REG(WRAM(i)) = be32(blocks[b] + 4*i);   // wajib 16 word
    REG(CTRL) = START | (b == 0 ? FIRST_BLK : 0) | (b == nblocks-1 ? LAST_BLK : 0);
    if (wait_done()) { /* tangani error / timeout */ return -1; }
}
// MSG_DONE = 1; baca HRAM_DIGEST[0..7]
```

#### Mode 1 (AUTO_PAD = 1)
```c
REG(MSG_LEN) = len;
if (len > 0xFFFFFFFFUL) return -1;         // host-side check: 32-bit batas desain
size_t off = 0, rem = len; int first = 1;
do {
    size_t n = rem < 64 ? rem : 64;                  // n = 0 untuk pesan kosong
    for (i = 0; i < (n + 3) / 4; i++)                // hanya ceil(n/4) word; sisanya diabaikan/ditimpa
        REG(WRAM(i)) = be32_partial(msg + off + 4*i); // lihat catatan be32_partial di atas
    REG(CTRL) = START | AUTO_PAD | (first ? FIRST_BLK : 0);
    if (wait_done()) { /* tangani error / timeout */ return -1; }
    off += n; rem -= n; first = 0;
} while (!(REG(STATUS) & MSG_DONE));
// baca HRAM_DIGEST[0..7]
```
Loop ini otomatis benar untuk `len % 64 == 0` (termasuk `len = 0`): setelah blok data penuh terakhir (64 byte) hardware menjalankan blok padding sendiri dan baru men-set `MSG_DONE`. Host **tidak** perlu mengirim blok kosong atau dummy write.

Jumlah word yang wajib ditulis host per START (Mode 1): 16 untuk blok data penuh (`n = 64`), `ceil(n/4)` untuk blok sisa (`n < 64`), 0 untuk `n = 0`. Hardware tidak dapat mendeteksi jika host menulis kurang untuk blok penuh (lihat Fase 5, hardening opsional).

---

## 4. Spesifikasi Modul

Semua modul: Verilog-2001, satu clock `clk`, register datapath **tanpa reset** (nilainya selalu di-load sebelum dipakai; **pengecualian: `mc.v`** mempertahankan reset async dari baseline §4.6; **`hram.v`** juga memiliki `rst_n` untuk reset ke 0 agar digest awal deterministik); register kontrol memakai reset `reset_n` async-assert/sync-release. Paket bersama di `sha256_defs.vh` (dengan include guard `ifndef SHA256_DEFS_VH`).

### 4.0. `sha256_defs.vh`
```verilog
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
```
*Catatan:* makro dipakai dengan operand 32-bit di konteks 32-bit; berikan argumen berupa sinyal (bukan ekspresi) agar lebar tidak ambigu. `BSIG0/BSIG1` dipakai testbench/model; `mc.v` memakai ekspresi rotasi persis seperti `project.v` (§4.6).

### 4.1. `k_rom.v`
```verilog
module k_rom (
    input  wire        clk,
    input  wire [5:0]  addr,
    output reg  [31:0] q        // registered output: q(t+1) = K[addr(t)]
);
```
64 konstanta (Lampiran A). Diinisialisasi dari `case` atau `$readmemh("k_rom.hex")`/`.mif`. Tambahkan atribut sintesis `(* romstyle = "M10K" *)` (verifikasi nama atribut di dokumentasi Quartus versi yang dipakai) agar tidak dipetakan ke logika. Output ter-register ⇒ **latensi 1 siklus**; aturan prefetch di §4.9.

### 4.2. `hram.v`
```verilog
module hram (
    input  wire         clk,
    input  wire         rst_n,           // reset ke 0 (digest awal deterministik; pengecualian aturan §4)
    input  wire         we,              // 1 siklus (FINALIZE)
    input  wire [255:0] d,               // dari hash_adder
    output wire [255:0] q                // digest saat ini, {H0..H7}, H0 = [255:224]
);
```
8×32 **flip-flop**, bukan BRAM. `rst_n` me-reset ke 0 (pengecualian "datapath tanpa reset" di §4; dijelaskan di §11). Pembacaan host (mux 8:1 → register `avs_readdata`) dilakukan di CSR.

### 4.3. `wram.v` — Working Word Register (Shift Register)
```verilog
module wram (
    input  wire        clk,
    // write port dari host (per word)
    input  wire        host_we,
    input  wire [3:0]  host_idx,
    input  wire [31:0] host_data,
    // shift (PAD | LOAD | PROC)
    input  wire        shift_en,
    input  wire [31:0] shift_in,         // masuk ke w[15]
    // tap tetap
    output wire [31:0] w0, w1, w9, w14
);
```
* **16×32 flip-flop** (512 FF). Bukan BRAM (butuh 4 tap baca bersamaan) dan bukan MLAB.
* Perilaku: `if (host_we) w[host_idx] <= host_data; else if (shift_en) begin w[i] <= w[i+1] (i=0..14); w[15] <= shift_in; end`. `host_we` dan `shift_en` **tidak boleh aktif bersamaan** (dijamin top karena host write dibuang saat BUSY); pasang assertion di simulasi.
* Tap: `w0 = w[0]` (W[n-16] / word masuk), `w1 = w[1]` (W[n-15]), `w9 = w[9]` (W[n-7]), `w14 = w[14]` (W[n-2]). Tidak ada mux baca.
* Isi WRAM **tak terdefinisi** setelah blok selesai; host harus menulis ulang kata yang dibutuhkan (§3.5).

### 4.4. `pad_fn.v` — Padding Unit (kombinasional, 1 word per siklus)
```verilog
module pad_fn (
    input  wire [3:0]  idx,         // indeks word 0..15 (pad_cnt)
    input  wire [31:0] din,         // w0 (word yang keluar dari ujung shift register)
    input  wire [5:0]  keep,        // jumlah byte pesan yang dipertahankan (0..63)
    input  wire        ins80,       // sisipkan 0x80 pada byte ke-keep
    input  wire        inslen,      // sisipkan panjang 64-bit di word 14,15
    input  wire [63:0] len_bits,    // {29'b0, msg_len_q, 3'b0}
    output wire [31:0] dout
);
```
Definisi (persis seperti model):
```text
d    = signed(keep) - signed(4*idx)     // WAJIB signed, lebar >= 8 bit
kb   = (d <= 0) ? 0 : (d >= 4) ? 4 : d
mask = (kb == 0) ? 0 : (32'hFFFF_FFFF << (32 - 8*kb))
dout = din & mask
if (ins80  && (keep >> 2) == idx) dout |= 8'h80 << (24 - 8*(keep & 3))
if (inslen && idx == 14) dout |= len_bits[63:32]
if (inslen && idx == 15) dout |= len_bits[31:0]
```
#### Catatan Verilog
```
wire signed [7:0] d  = $signed({2'b00, keep}) - $signed({2'b00, idx, 2'b00});
wire        [2:0] kb = (d <= 0) ? 3'd0 : (d >= 4) ? 3'd4 : d[2:0];
```
Jangan menulis `keep - 4*idx` unsigned. Selisih negatif akan menjadi 4 dan byte sampah WRAM lolos mask.

Parameter per kasus (dipilih FSM):

| Kasus | `keep` | `ins80` | `inslen` |
|:---|:-:|:-:|:-:|
| Blok sisa, `bytes_left < 56` (TAIL) | `bytes_left` | 1 | 1 |
| Blok sisa, `56 ≤ bytes_left < 64` (OVF), blok pertama | `bytes_left` | 1 | 0 |
| Blok otomatis setelah OVF (`LEN`) | 0 | 0 | 1 |
| Blok otomatis setelah blok penuh terakhir (`FULL`) | 0 | 1 | 1 |

### 4.5. `me.v` — Message Expansion
```verilog
module me (
    input  wire        sched_en,           // 1 jika n >= 16
    input  wire [31:0] w0, w1, w9, w14,
    output wire [31:0] w_n
);
// w_n = w0 + (sched_en ? (SIG0(w1) + w9 + SIG1(w14)) : 32'd0)
```
Gunakan **gating operand** (`sched_en ? ... : 0`), bukan mux setelah adder, agar tidak menambah level pada critical path. `w_n` kombinasional.

### 4.6. `mc.v` — Compression Core **diturunkan dari `baseline/project.v`**, dengan Precompute `hkw`

`mc.v` **bukan** ditulis ulang dari spesifikasi SHA-256. Berkas ini dibuat dengan menyalin `baseline/project.v` (modul `tt_um_xeniarose_sha256` dari `tt07-sha256`), membuang antarmuka pin Tiny Tapeout, lalu memodifikasinya. **Nama sinyal baseline dipertahankan**: `register_file[9:0]`, makro `` `A_reg `` … `` `K_reg ``, `s1`, `ch`, `s0`, `maj`, `temp1`, `temp2`, `clk`, `rst_n`. Penanda pada kode: `[BASELINE]` = disalin dari `project.v` tanpa perubahan; `[MODIFIED]` = diubah; `[NEW]` = ditambahkan. Peta lengkap dan aturan penyalinan ada di §12.3.

```verilog
`default_nettype none                              // [BASELINE]

module mc #(
    parameter LEGACY_EN = 1               // [NEW] 0 = buang Legacy Step Mode (§12.4)
) (
    input  wire         clk,              // [BASELINE]
    input  wire         rst_n,            // [BASELINE] reset async
    input  wire         load,             // [NEW] siklus LOAD (cyc = 0)
    input  wire         round_en,         // [NEW] pengganti "tulis alamat 63" (PROC atau LRND)
    input  wire [255:0] h_base,           // [NEW] {A..H} awal = first_eff ? IV : HRAM
    input  wire [31:0]  k_val,            // [NEW] K[n] dari k_rom
    input  wire [31:0]  w_n,              // [NEW] W[n] dari me.v
    // Legacy Step Mode (LEGACY_EN = 1; bila 0 ikat input ke 0)
    input  wire         leg_prep,         // [NEW] hkw <= H_reg + K_reg + W_reg
    input  wire         leg_we,           // [NEW] tulis register_file[leg_idx]
    input  wire [3:0]   leg_idx,          // [NEW] 0..7 = A..H, 8 = W, 9 = K
    input  wire [31:0]  leg_data,         // [NEW]
    output wire [31:0]  leg_w, leg_k,     // [NEW] W_reg, K_reg (jendela baca legacy)
    output wire [255:0] state_out         // [NEW] {A,B,C,D,E,F,G,H}
);

  reg [ 31 : 0 ] register_file [ 9 : 0 ];          // [BASELINE]

  `define A_reg register_file[0]                   // [BASELINE] dst. sampai K_reg
  `define B_reg register_file[1]
  `define C_reg register_file[2]
  `define D_reg register_file[3]
  `define E_reg register_file[4]
  `define F_reg register_file[5]
  `define G_reg register_file[6]
  `define H_reg register_file[7]
  `define W_reg register_file[8]                   // hanya dipakai Legacy Step Mode
  `define K_reg register_file[9]                   // hanya dipakai Legacy Step Mode

  reg [ 31 : 0 ] hkw;                              // [NEW] H_t + K_t + W_t

  wire [ 31 : 0 ] s1 =                             // [BASELINE] verbatim
    {`E_reg[5:0],`E_reg[31:6]} ^ {`E_reg[10:0],`E_reg[31:11]} ^ {`E_reg[24:0],`E_reg[31:25]};
  wire [ 31 : 0 ] ch = (`E_reg & `F_reg) ^ ((~`E_reg) & `G_reg);   // [BASELINE]
  // [MODIFIED] baseline: temp1 = `H_reg + s1 + ch + `K_reg + `W_reg
  wire [ 31 : 0 ] temp1 = hkw + s1 + ch;           // H+K+W sudah dijumlahkan satu siklus lebih awal
  wire [ 31 : 0 ] s0 =                             // [BASELINE] verbatim
    {`A_reg[1:0],`A_reg[31:2]} ^ {`A_reg[12:0],`A_reg[31:13]} ^ {`A_reg[21:0],`A_reg[31:22]};
  wire [ 31 : 0 ] maj = (`A_reg & `B_reg) ^ (`A_reg & `C_reg) ^ (`B_reg & `C_reg);  // [BASELINE]
  wire [ 31 : 0 ] temp2 = s0 + maj;                // [BASELINE]

  always @(posedge clk or negedge rst_n) begin : mc_proc   // [MODIFIED] sebelumnya io_proc
    if (!rst_n) begin                              // [BASELINE] semua register di-reset 0
      register_file[0] <= 32'h0;
      register_file[1] <= 32'h0;
      register_file[2] <= 32'h0;
      register_file[3] <= 32'h0;
      register_file[4] <= 32'h0;
      register_file[5] <= 32'h0;
      register_file[6] <= 32'h0;
      register_file[7] <= 32'h0;
      register_file[8] <= 32'h0;
      register_file[9] <= 32'h0;
      hkw <= 32'h0;                                // [NEW]
    end else if (load) begin                       // [NEW] muat state awal blok
      {`A_reg,`B_reg,`C_reg,`D_reg,`E_reg,`F_reg,`G_reg,`H_reg} <= h_base;
      hkw <= h_base[31:0] + k_val + w_n;           // H_0 + K_0 + W_0
    end else if (round_en) begin                   // [MODIFIED] sebelumnya: io_clk, !io_we, case 63
      `A_reg <= temp1 + temp2;                     // [BASELINE] isi `case 63`, persis
      `B_reg <= `A_reg;
      `C_reg <= `B_reg;
      `D_reg <= `C_reg;
      `E_reg <= `D_reg + temp1;
      `F_reg <= `E_reg;
      `G_reg <= `F_reg;
      `H_reg <= `G_reg;
      hkw    <= `G_reg + k_val + w_n;              // [NEW] H_{t+1} = G_t ; K_{t+1}, W_{t+1}
    end else if (LEGACY_EN && leg_prep) begin      // [NEW]
      hkw <= `H_reg + `K_reg + `W_reg;
    end else if (LEGACY_EN && leg_we) begin        // [NEW] padanan tulis register di project.v
      if (leg_idx <= 4'd9) register_file[leg_idx] <= leg_data;
    end
  end

  assign state_out = {`A_reg,`B_reg,`C_reg,`D_reg,`E_reg,`F_reg,`G_reg,`H_reg};  // [NEW]
  assign leg_w = `W_reg;                           // [NEW]
  assign leg_k = `K_reg;                           // [NEW]

endmodule

`undef A_reg                                       // [NEW] cegah kebocoran makro ke berkas lain
`undef B_reg
`undef C_reg
`undef D_reg
`undef E_reg
`undef F_reg
`undef G_reg
`undef H_reg
`undef W_reg
`undef K_reg
`default_nettype wire                              // [NEW] pulihkan (baseline tidak memulihkan)
```

Catatan:
* `temp1` identik secara aritmetika dengan baseline (penjumlahan modulo 2^32 bersifat asosiatif dan komutatif) selama `hkw = H_reg + K_reg + W_reg` pada nilai register yang sama. Cek di Python (20.000 round acak + 64 round vs `hashlib`) lolos, tetapi bukti yang berlaku tetap `tb_baseline_equiv` (§12.6, T1).
* Prioritas `load > round_en > leg_prep > leg_we`. Keempatnya tidak pernah aktif bersamaan (dijamin FSM dan CSR); pasang assertion di simulasi.
* Pada siklus PROC terakhir (round 63) `hkw` menghitung nilai yang tak terpakai; tidak berbahaya. Pada `LRND`, `hkw` ikut ter-update dari `k_val`/`w_n` yang tak bermakna dan tak terpakai (`LPREP` selalu menghitung ulang).
* Reset async baseline dipertahankan (pengecualian dari aturan "datapath tanpa reset" di §4). Flip-flop Cyclone V punya clear asinkron sehingga biaya area diharapkan kecil; konfirmasi di laporan fitter.
* `register_file[8]` (`W`) dan `[9]` (`K`) tidak dipakai mode otomatis (W dari WRAM/ME, K dari K-ROM). Dengan `LEGACY_EN = 0` keduanya konstan 0 dan dibuang sintesis (periksa di laporan).
* Karena nama register sama, `tb_baseline_equiv` dapat membandingkan langsung `baseline.register_file[i]` dengan `mc.register_file[i]` secara hierarkis.

### 4.7. `hash_adder.v`
```verilog
module hash_adder (
    input  wire [255:0] h_base,       // first_eff ? IV : HRAM  (BUKAN HRAM mentah)
    input  wire [255:0] state_final,  // state_out dari mc
    output wire [255:0] h_new         // 8 penjumlahan 32-bit mod 2^32, per lane
);
```
`h_new[i] = h_base[i] + state_final[i]`. Masukan `h_base` **harus** sinyal yang sama dengan yang dipakai `mc` pada siklus LOAD.

### 4.8. `sha256_core.v` — Integrasi Datapath + FSM
```verilog
module sha256_core #(parameter LEGACY_EN = 1) (
    input  wire         clk, rst_n,
    // dari CSR
    input  wire         soft_rst,
    input  wire         start_req,      // 1 siklus, hanya bila START diterima
    input  wire         first_in, last_in, auto_in,   // nilai pada write START
    input  wire [31:0]  msg_len_reg,    // nilai REG_MSG_LEN saat ini
    input  wire         host_we,
    input  wire [3:0]   host_idx,
    input  wire [31:0]  host_data,
    // Legacy Step Mode (§12.4; ikat ke 0 bila LEGACY_EN = 0)
    input  wire         leg_step_req,   // 1 siklus, hanya bila LEG_STEP diterima CSR
    input  wire         leg_we,
    input  wire [3:0]   leg_idx,
    input  wire [31:0]  leg_data,
    // ke CSR
    output wire         fsm_busy,
    output wire [5:0]   round,          // 0..63 di PROC, selain itu 0
    output wire         blk_inc,        // 1 siklus per kompresi (FINALIZE)
    output wire         done_pulse,     // 1 siklus saat seluruh pekerjaan START selesai
    output wire         msg_done_pulse, // done_pulse & pesan selesai
    output wire [255:0] digest,         // = hram.q
    output wire [255:0] state_dbg,      // A..H dari mc (jendela legacy / debug)
    output wire [31:0]  leg_w, leg_k    // W_reg, K_reg dari mc (jendela legacy)
);
```
Isi: `sha256_fsm`, `k_rom`, `wram`, `pad_fn`, `me`, `mc`, `hash_adder`, `hram`, serta mux `h_base` dan mux `shift_in`:
```verilog
wire        first_eff = first_q & ~second_pass;
wire [255:0] h_base   = first_eff ? `NIST_IV : hram_q;
wire [31:0]  shift_in = (state == PAD) ? pad_y : w_n;
```

### 4.9. `sha256_fsm.v` — Controller

**State (3-bit):** `IDLE=0, PAD=1, LOAD=2, PROC=3, FIN=4`. Tidak ada state `DONE`; selesai ditandai pulsa ke CSR. Bila `LEGACY_EN = 1` ditambah `LPREP=5, LRND=6` (Legacy Step Mode, §12.4); lima state inti tidak berubah.

**Register internal:** `cyc[6:0]`, `pad_cnt[3:0]`, `first_q`, `last_q`, `auto_q`, `second_pass`, `cls` (DATA / FULL_LAST / OVF / TAIL / RAW), `pass2` (NONE / FULL / LEN), `msg_last`, `keep[5:0]`, `ins80`, `inslen`, `msg_len_q[31:0]`, `bytes_left[31:0]`.

**Keputusan di `IDLE` saat `start_req`:**
```text
first_q <= first_in;  last_q <= last_in;  second_pass <= 0
if (first_in) begin auto_q <= auto_in; msg_len_q <= msg_len_reg; bytes_left <= msg_len_reg; end
bl = first_in ? msg_len_reg : bytes_left

if (!auto_eff)                 cls=RAW,       msg_last=last_in, pass2=NONE, PAD tidak dipakai
else if (bl > 64)              cls=DATA,      msg_last=0,       pass2=NONE
else if (bl == 64)             cls=FULL_LAST, msg_last=1,       pass2=FULL
else if (bl >= 56)             cls=OVF,       msg_last=1,       pass2=LEN,  PAD(keep=bl, ins80=1, inslen=0)
else                           cls=TAIL,      msg_last=1,       pass2=NONE, PAD(keep=bl, ins80=1, inslen=1)
(auto_eff = first_in ? auto_in : auto_q)
// pad_used = (cls == TAIL) || (cls == OVF)
// RAW, DATA, dan FULL_LAST pass-1 langsung ke LOAD (tidak melalui PAD)
pad_cnt <= 0;  cyc <= 0;
next = pad_used ? PAD : LOAD;
```

**Tabel kontrol per state:**

| State | Durasi | `k_addr` | `shift_en` | `shift_in` | Aksi |
|:---|:-:|:---|:-:|:---|:---|
| `IDLE` | ≥ 1 | 0 | 0 | — | Tunggu `start_req` (atau `leg_step_req` → `LPREP` bila `LEGACY_EN`); keputusan di atas (1 siklus) |
| `PAD` | 16 | 0 | 1 | `pad_y` | `pad_idx = pad_cnt`; `pad_cnt++`; pada `pad_cnt == 15` → `LOAD` |
| `LOAD` | 1 | 1 | 1 | `w_n` (n=0) | `load=1`; `cyc = 0`; → `PROC`; `sched_en = 0` |
| `PROC` | 64 | `(cyc+1) & 63` | 1 | `w_n` | `round_en=1`; `sched_en = (cyc ≥ 16)`; `cyc` 1→64; `round = cyc-1`; pada `cyc == 64` → `FIN`;  |
| `FIN` | 1 | 0 | 0 | — | `hram_we=1`; `blk_inc`; lihat di bawah |
| `LPREP` | 1 | 0 | 0 | — | (`LEGACY_EN`) `leg_prep=1`; → `LRND` |
| `LRND` | 1 | 0 | 0 | — | (`LEGACY_EN`) `round_en=1`, `shift_en=0`; `done_pulse <= 1` (tanpa `msg_done_pulse`, tanpa `blk_inc`); → `IDLE` |

```text
sched_en = (state == PROC) && (cyc >= 16);  // di semua state lain sched_en = 0
round    = (state == PROC) ? cyc - 1 : 0;   // gated: tidak menampilkan nilai sisa di PAD/LOAD pass-2
```

**Aksi `FIN`:**
```text
hram <= hash_adder(h_base, state)         // first_eff dipakai di sini juga
if (pass2 != NONE && !second_pass):       // blok otomatis
    second_pass <= 1
    pass2==FULL: keep=0, ins80=1, inslen=1
    pass2==LEN : keep=0, ins80=0, inslen=1
    pad_cnt <= 0;  cyc <= 0;  next = PAD     // cyc harus 0 saat LOAD pass-2
else:
    if (cls == DATA) bytes_left <= bytes_left - 64
    done_pulse <= 1;  if (msg_last) msg_done_pulse <= 1
    next = IDLE
```

**Aturan K-ROM prefetch (wajib):** `k_addr = 0` pada `IDLE`, `PAD`, `FIN`, `LPREP`, dan `LRND`; `k_addr = (cyc+1) & 63` pada `LOAD`/`PROC` (dengan `cyc = 0` di LOAD). Hasilnya `k_val` pada siklus `cyc` = `K[cyc]`, tepat saat `mc` membutuhkannya untuk menghitung `hkw` round berikutnya. Karena `IDLE` selalu menyajikan alamat 0 minimal satu siklus sebelum `LOAD`, `K[0]` sudah ada di keluaran saat LOAD.

`fsm_busy = (state != IDLE)`. `soft_rst` mengembalikan FSM ke `IDLE` dan menghapus `second_pass`.

### 4.10. `sha256_csr.v` dan `sha256_accelerator.v` (Top)
`sha256_csr.v` menyimpan register host dan semua flag; `sha256_accelerator.v` menyambungkan CSR ↔ core.

Tanggung jawab CSR:
* **Dekode alamat** dan `avs_readdata` ter-register (read latency 1); `WRAM_DATA` dibaca 0.
* **`busy_q`**: di-set pada write START yang diterima (siklus yang sama dengan write), di-clear oleh `done_pulse` atau `soft_rst`. `BUSY` pada STATUS = `busy_q`. Ini menutup celah 1 siklus antara write START dan reaksi FSM.
* **Penerimaan START** (saat write `CTRL` dengan `START=1`, `SOFT_RST=0`): jika `LEG_STEP=1` pada write yang sama → `ERR`, keduanya diabaikan; jika `busy_q` → `ERR`; jika `FIRST_BLK=0 && !msg_active` → `ERR`; selain itu `busy_q<=1`, `msg_active<=1`, hapus `BLOCK_DONE/MSG_DONE`, dan register `start_req/first/last/auto` untuk dikirim ke core pada siklus berikutnya.
* **Tulis WRAM**: `host_we = avs_write & addr∈[0x04,0x13] & ~busy_q`; jika `busy_q` → `ERR`.
* **Flag**: `BLOCK_DONE <= 1` pada `done_pulse`; `MSG_DONE <= 1` dan `msg_active <= 0` pada `msg_done_pulse`; W1C dan `soft_rst` seperti §3.2.
* **`BLOCK_CNT`** bertambah pada `blk_inc`; `soft_rst` mengosongkannya.
* **`irq`** `= irq_en & (msg_done | err)`.
* **Read mux** digest: `HRAM_DIGEST[i]` = `digest[255-32*i -: 32]`.
* **Jendela legacy** (`LEGACY_EN`): alamat `0x20..0x29`; baca = `state_dbg`/`leg_w`/`leg_k` (word `i` = `A,B,C,D,E,F,G,H,W,K`); tulis → `leg_we` bila `~busy_q`, selain itu `ERR`; `0x2A..0x3F` baca 0.
* **`LEG_STEP`** (write `CTRL` bit 6 dengan `START=0`, `SOFT_RST=0`): jika `busy_q` atau `START=1` → `ERR`, diabaikan; selain itu `busy_q<=1`, hapus `BLOCK_DONE/MSG_DONE`, kirim `leg_step_req` satu siklus ke core. `msg_active` dan `BLOCK_CNT` tidak berubah. Selesai oleh `done_pulse` → `BLOCK_DONE` (tanpa `MSG_DONE`).

---

## 5. Timing

### 5.1. Urutan 66 Siklus (blok data penuh / Mode 0)

```text
Siklus:   S       0 (LOAD)    1 (R0)  ...  64 (R63)    65 (FIN)
FSM:      IDLE    LOAD        PROC         PROC        FIN
          (keputusan)
WRAM:             geser n=0   geser n=1..64
K-ROM:    addr 0  addr 1      addr 2 ...   addr 1*     addr 0
MC:               load A..H   round 0 ...  round 63
                  hkw0=H+K0+W0 hkw1..       (hkw tak terpakai)
Adder/HRAM:                                             H_new = h_base + state ; HRAM <- H_new
```
`*` Pada `cyc = 63` alamat = `(63+1) & 63 = 0` (wrap) dan pada `cyc = 64` alamat = 1; nilai K yang keluar dari keduanya tidak terpakai.

### 5.2. Durasi per Kasus (diverifikasi model; lihat Lampiran C)

| Kasus (dihitung dari siklus keputusan di IDLE sampai pekerjaan START selesai) | Kompresi | Siklus |
|:---|:-:|:-:|
| Mode 0, satu blok (juga Mode 1 blok data `bytes_left > 64`) | 1 | 1 + 66 = **67** |
| Mode 1, sisa `< 56` byte (TAIL; termasuk pesan kosong) | 1 | 1 + 16 (PAD) + 66 = **83** |
| Mode 1, sisa `56..63` byte (OVF) | 2 (otomatis) | 1 + (16 + 66) + (16 + 66) = **165** |
| Mode 1, sisa tepat 64 byte (FULL_LAST) | 2 (otomatis) | 1 + 66 + (16 + 66) = **149** |
| Legacy `LEG_STEP` (§12.4) | 0 | 1 + 2 = **3** *(belum diverifikasi model)* |

*(FULL_LAST: blok data penuh tanpa PAD, lalu satu blok padding otomatis yang memakai PAD. Keempat angka di tabel ini diverifikasi oleh model, Lampiran C.)*

### 5.3. Model Performa (ganti klaim v1)
```text
T_blok ≈ N_tulis·t_tulis + t_start + t_poll + T_core
N_tulis = 16 (Mode 0 / blok penuh),  T_core = 67 / f_clk   (≈ 0,67 µs @ 100 MHz)
```
* **Core saja @ 100 MHz:** ≈ 1,5 juta blok/s (≈ 760 Mbit/s).
* **Bus ideal (1 word/siklus):** 16 + 67 = 83 siklus ⇒ ≈ 1,2 juta blok/s (≈ 617 Mbit/s).
* **Dari HPS lewat lightweight bridge:** `t_tulis` jauh lebih besar dari 1 siklus clock; hampir pasti waktu bus mendominasi `T_core`. **Ukur di board** (§7.4) dan laporkan hasil terukur, bukan angka teoretis. Bandingkan dengan baseline dalam **siklus** pada clock yang sama atau waktu terukur.
* Tidak ada overlap load/compute karena WRAM adalah buffer ekspansi (trade-off area; solusi di Fase 5).

---

## 6. Struktur File

```text
quartus_sha256_soc/
├── baseline/                  (tt07-sha256 ASLI, TIDAK DIUBAH; hanya untuk simulasi/diff)
│   ├── project.v              (tt_um_xeniarose_sha256)
│   ├── info.yaml              (bila ada)
│   └── LICENSE                (Apache-2.0)
├── rtl/
│   ├── sha256_defs.vh
│   ├── k_rom.v            (+ k_rom.hex / .mif)
│   ├── wram.v
│   ├── pad_fn.v
│   ├── me.v
│   ├── mc.v               (TURUNAN baseline/project.v; §4.6, §12)
│   ├── hash_adder.v
│   ├── hram.v
│   ├── sha256_fsm.v
│   ├── sha256_core.v
│   ├── sha256_csr.v
│   └── sha256_accelerator.v
├── tb/
│   ├── tb_unit_{k_rom,wram,pad_fn,me,mc}.sv
│   ├── tb_baseline_equiv.sv  (Fase 1, §12.6 T1)
│   ├── tb_baseline_driven.sv (Fase 1/2, §12.6 T2)
│   ├── tb_core_raw.sv        (Fase 1)
│   ├── tb_core_autopad.sv    (Fase 2)
│   ├── tb_accel_avalon.sv    (Fase 3, dengan Avalon BFM)
│   └── vectors/              (dibuat oleh tools/gen_vectors.py)
├── tools/
│   ├── sha256_arch_model.py  (model acuan cycle-level)
│   ├── baseline_ref.py       (transkripsi round project.v, §12.7)
│   └── gen_vectors.py
├── quartus/
│   ├── sha256_soc.sdc
│   ├── build.tcl
│   └── sha256_accelerator_hw.tcl   (komponen Platform Designer)
└── sw/
    └── test_sha256.c          (program uji di HPS)
```
Proyek ini **turunan baseline**, bukan standalone: salinan asli `tt07-sha256` disimpan **tidak diubah** di `baseline/` (untuk diff, bukti integrasi, dan acuan `tb_baseline_equiv`); semua modifikasi dilakukan pada berkas di `rtl/`. Jangan menimpa `baseline/project.v` / `info.yaml`. Berkas turunan mempertahankan header SPDX/hak cipta asli (§12.1).

---

## 7. Verifikasi

### 7.1. Vektor Uji (golden dari `hashlib`)

| Kasus | Input | SHA-256 |
|:---|:---|:---|
| Kosong | `""` (0 B) | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| NIST 1 blok | `"abc"` | `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad` |
| 55 B | `"a" × 55` | `9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318` |
| 56 B | `"a" × 56` | `b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a` |
| 63 B | `"a" × 63` | `7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34` |
| 64 B | `"a" × 64` | `ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb` |
| 119 B | `"a" × 119` | `31eba51c313a5c08226adf18d4a359cfdfd8d2e816b13f4af952f7ea6584dcfb` |
| 120 B | `"a" × 120` | `2f3d335432c70b580af0e8e1b3674a7c020d683aa5f73aaaedfdc55af904c21c` |
| NIST 56 B (OVF) | `abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq` | `248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1` |
| NIST 112 B (2 blok data) | `abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu` | `cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1` |
| NIST 1 juta `a` | `"a" × 1.000.000` | `cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0` |

*(Hash 56 B NIST di atas 64 karakter hex; v1 salah satu karakter. Testbench harus memeriksa panjang string sebelum membandingkan.)*

Setiap vektor dijalankan di **Mode 0 (pesan di-pad software)** dan **Mode 1**, pada **satu instance DUT berturut-turut tanpa reset** (menguji pelatchan `first_q` dan sisa WRAM/HRAM).

### 7.2. Skenario Wajib

| Area | Skenario |
|:---|:---|
| Back-to-back | Hash `"abc"` dua kali berturut-turut; urutan panjang acak tanpa reset |
| Regresi acak | Panjang 0–400 B, data acak, masing-masing ≥ 3 kali, Mode 0 dan Mode 1; golden dari `hashlib` |
| Garbage | Byte tak terpakai pada word parsial terakhir diisi acak (harus di-mask `pad_fn`); WRAM tak ditulis ulang pada word di luar `ceil(n/4)` |
| Kasus batas | 0, 1, 55, 56, 57, 63, 64, 65, 119, 120, 127, 128 B |
| Perilaku abnormal | START saat BUSY; tulis WRAM saat BUSY; `START` dengan `FIRST_BLK=0` tanpa pesan aktif; `SOFT_RST` di tengah blok lalu pesan baru; `FIRST_BLK=1` saat `MSG_ACTIVE=1` |
| Status/IRQ | `BUSY` aktif tepat setelah write START; `BLOCK_DONE/MSG_DONE` W1C; set-menang pada kolisi; `irq` aktif sesuai `REG_IRQ_MASK` (BLOCK_DONE_IE / MSG_DONE_IE / ERR_IE); turun setelah flag di-W1C |
| Timing siklus | Assertion: 67 / 83 / 149 / 165 sesuai §5.2; `ROUND` 0..63 |
| Atomisitas digest | Baca `HRAM_DIGEST` saat BUSY: nilai selalu utuh 256-bit. Mode 0/DATA/TAIL: tidak berubah sampai satu-satunya FIN. OVF/FULL_LAST: berubah **dua kali** (FIN pass-1 dan FIN pass-2), keduanya saat BUSY masih tinggi. Periksa bahwa tiap pembacaan menghasilkan 256-bit yang koheren, bukan nilai acak |
| Cocok model | Bandingkan `hkw`, `state_out`, `w[]`, `cyc`, `state` setiap clock dengan dump `sha256_arch_model.py` |
| Ekuivalensi baseline | `A..H` setelah tiap round identik dengan modul `tt_um_xeniarose_sha256` asli (T1); digest baseline-driven = digest akselerator = `hashlib` (T2); lihat §12.6 |
| Legacy Step Mode | `LEG_STEP` = 3 siklus; `ERR` untuk tulis jendela/`LEG_STEP` saat BUSY dan `START`+`LEG_STEP` bersamaan; tulis jendela di antara blok tidak merusak digest (T3, T4) |
| Pesan sangat panjang | Blok akhir OVF, FULL_LAST, TAIL dengan MSG_LEN ∈ {2²⁹−1, 2²⁹, 2³²−1}. `msg_len_q` dan `bytes_left` di-deposit lewat hierarki (`force` / `deposit` di SystemVerilog, atau port backdoor khusus testbench). Tujuan: cakupan `len_bits[63:32] ≠ 0` yang tidak bisa dicapai dengan pesan fisik di testbench ≤ 400 B. *Bug `cyc` pass-2 yang sebenarnya (bila `cyc` tidak di-reset) akan tertangkap lebih awal oleh assertion siklus 67/83/149/165 di panjang pesan mana pun.* |
| pad_fn signed | Seluruh `keep` 0..63 × `idx` 0..15 dengan `din` berisi sampah acak; hasil harus sama dengan model. *Opsional: satu run Verilator 2²⁹ byte (≈ 560 juta siklus) sebagai bukti ujung ke ujung.* |

### 7.3. Unit Test per Modul (dikerjakan **sebelum** integrasi)
`k_rom` (64 konstanta + latensi 1 siklus) · `wram` (host write, shift, tap) · `pad_fn` (seluruh `keep` 0..63 × 4 kombinasi `ins80/inslen` vs model) · `me` (W16..W63 vs Python) · `mc` (satu blok "abc" yang dikemudikan testbench, **dan** `tb_baseline_equiv` terhadap modul baseline asli, §12.6).

### 7.4. Uji Board
Program C di HPS (`sw/test_sha256.c`) membandingkan hasil dengan OpenSSL/`sha256sum` untuk panjang acak, lalu mengukur waktu nyata per blok (termasuk bus) dengan polling dan dengan IRQ. Catat Fmax dari Quartus dan ukuran throughput terukur.

---

## 8. Anggaran Resource dan Timing (Pra-Sintesis)

### 8.1. Flip-Flop (dihitung dari arsitektur)

| Blok | FF |
|:---|:-:|
| `wram` (16×32) | 512 |
| `mc` (A..H = 256, `hkw` = 32) | 288 |
| `hram` (8×32) | 256 |
| `sha256_fsm` (state, `cyc`, `pad_cnt`, `msg_len_q`, `bytes_left`, flag/param) | ≈ 90 |
| `sha256_csr` (`MSG_LEN`, `BLOCK_CNT`, flag, `readdata`, kontrol) | ≈ 105 |
| Legacy Step Mode (`W_reg`, `K_reg` di `mc`; flag `leg_step_req`; state LPREP/LRND memakai 3-bit state yang sama) | ≈ 66 |
| **Total** | **≈ 1.320** (≈ 1.250 bila `LEGACY_EN = 0`) |

### 8.2. Estimasi ALM dan Memori

| Blok | ALM (perkiraan) | M10K | DSP |
|:---|:-:|:-:|:-:|
| `k_rom` | ~0–5 | 1 (2 kbit terpakai) | 0 |
| `wram` (FF + mux 3-sumber) | 300–520 | 0 | 0 |
| `pad_fn` | 40–80 | 0 | 0 |
| `me` | 70–120 | 0 | 0 |
| `mc` | 300–450 | 0 | 0 |
| `hash_adder` (8×32 bit) | 128–170 | 0 | 0 |
| `hram` | 128–200 | 0 | 0 |
| `h_base` mux (256 bit) | 128–260 | 0 | 0 |
| `sha256_fsm` | 60–100 | 0 | 0 |
| `sha256_csr` + top | 90–160 | 0 | 0 |
| Legacy Step Mode (mux tulis `A..H` di `mc`, mux baca 10 word di CSR, 2 state FSM) | 150–350 *(perkiraan kasar)* | 0 | 0 |
| **Total** | **≈ 1.400–2.400 ALM** (≈ 3.600–6.200 LE-ekuivalen, rasio ≈ 2,6); ≈ 1.250–2.050 bila `LEGACY_EN = 0` | **1** | **0** |

* Pada `5CSEBA6U23I7` (≈ 41.900 ALM): **≈ 3–6%**. Angka ini perkiraan; **gantikan dengan laporan fitter Quartus** setelah kompilasi.
* **0 DSP:** SHA-256 tidak memakai perkalian; penjumlahan 32-bit dipetakan ke ALM carry chain.
* Cyclone V melaporkan **ALM**; angka LE hanya konversi kasar.

### 8.3. Analisis Fmax
Jalur kritis kandidat (perkiraan, untuk dikonfirmasi Timing Analyzer):

| Jalur | Isi | Level adder 32-bit |
|:---|:---|:-:|
| Round | `E → Σ1/Ch → hkw+Σ1+Ch → D+T1` atau `T1+T2 → A` | ≈ 2 |
| Precompute (`round_en`) | `w taps → σ0/σ1 → w0+σ0+w9+σ1 → (+G+K) → hkw` | ≈ 3 |
| Precompute (`load`) | `h_base[31:0] + k_val + w_n → hkw` | ≈ 1 |
| Precompute (`leg_prep`) | `H_reg + K_reg + W_reg → hkw` | ≈ 1 |

**Catatan `hkw` multi-sumber:** tiga cabang `if/else` menghasilkan tiga operand set menuju satu register `hkw`. Synth dapat membentuk 3 adder tree + 3:1 mux, atau 1 adder + mux operand di depan. Pastikan jalur `round_en` (precompute ≈ 3 level) tidak terbebani mux tambahan dari cabang `load`/`leg_prep`; bila perlu berikan adder terpisah untuk `leg_prep` dan mux hanya hasilnya. Konfirmasi dengan laporan Timing Analyzer (`LEGACY_EN = 0` vs `1`).

Dibanding v1 (ME + T1 + A dalam satu siklus, ≈ 6 level), jalur v2 ≈ 3 level. Jalur *precompute* kini yang terpanjang; gunakan gating operand di `me.v` (bukan mux) dan biarkan Quartus memakai ternary adder. **Fallback bila Fmax < target:**
1. Aktifkan retiming/physical synthesis, periksa fan-out `first_eff`/`h_base`.
2. Tambah satu register pada keluaran `w_n` (jadwal W berjalan dua siklus lebih awal) ⇒ latensi 67 siklus.
3. Turunkan target clock (mis. 80 MHz) dan catat di laporan.

Perhatikan: speed grade `I7` (5CSEBA6U23I7) berbeda dari `C7`; ikuti device yang dikompilasi.

**Checklist Fase 4 (gating sintesis):** verifikasi apakah HPS lightweight bridge mendukung 100 MHz (referensi Altera sering menggunakan 50 MHz); turunkan PLL jika perlu dan dokumentasikan.

---

## 9. Panduan Eksekusi untuk AI (urutan bertahap, uji di setiap langkah)

Jangan lanjut ke langkah berikut sebelum langkah sebelumnya lolos kriteria selesai. Model `sha256_arch_model.py` adalah **acuan perilaku**; RTL harus cocok dengan model per clock (terutama `state`, `cyc`, `hkw`, `A..H`).

| Langkah | Kerjakan | Kriteria selesai |
|:-:|:---|:---|
| 0 | Salin `sha256_arch_model.py`; buat `gen_vectors.py` (hasil: file `.hex` pesan + digest, panjang hex digest harus 64) dan `sha256_defs.vh`. **Tambahkan** `baseline/` (salinan asli `project.v`, `LICENSE`), `tools/baseline_ref.py`, dan perluas model dengan `LEG_STEP` (§12.7) | Skrip jalan; model lolos regresi sendiri; `baseline_ref.py` (64 round + IV) cocok dengan `hashlib` |
| 1 | `k_rom`, `hram`, `wram` (shift register), unit test | 64 K benar, latensi ROM 1 siklus; tap `[0,1,9,14]` benar setelah shift |
| 2 | `me`, `pad_fn`, unit test | W16..W63 sama dengan model; `pad_fn` sama dengan model untuk seluruh `keep` |
| 3 | `mc` **diturunkan dari `baseline/project.v`** (§12.3, langkah penyalinan 1–6) + `hash_adder`; `tb_baseline_equiv` (round-per-round vs modul baseline asli), lalu testbench satu blok "abc" pre-padded | `A..H` setelah tiap round **identik** dengan baseline asli pada ≥ 10.000 round acak (T1); `hkw`/`A..H` per clock sama dengan model; digest benar |
| 4 | `sha256_fsm` (**Mode 0 saja**, `PAD` dikunci tidak dipakai; ditambah state `LPREP/LRND` bila `LEGACY_EN`) + `sha256_core`; `tb_core_raw` | **Fase 1:** vektor NIST Mode 0, back-to-back, 67 siklus per blok; `LEG_STEP` = 3 siklus |
| 5 | Aktifkan `PAD`, kelas `DATA/FULL_LAST/OVF/TAIL`, `second_pass`; `tb_core_autopad` | **Fase 2:** seluruh panjang 0–400 B (acak) dan vektor §7.1 lolos; siklus 67/83/149/165; blok akhir dengan MSG_LEN ≥ 2²⁹ (§7.2) lolos |
| 6 | `sha256_csr` + `sha256_accelerator` (termasuk jendela legacy dan `LEG_STEP`); `tb_accel_avalon` dengan BFM | **Fase 3:** §7.2 (status, W1C, ERR, IRQ, kolisi) lolos; T3 (§12.6) lolos |
| 7 | Regresi penuh + 1 juta `a` (simulasi panjang; boleh versi Verilator); `tb_baseline_driven` (T2) dan regresi `LEGACY_EN = 0/1` (T4) | Semua vektor & acak lolos tanpa reset antar pesan; digest baseline-driven = digest akselerator; siklus bus baseline tercatat |
| 8 | `sha256_soc.sdc`, `build.tcl`, komponen Platform Designer, kompilasi | **Fase 4:** laporan ALM/FF/M10K/DSP dan Fmax dengan slack ≥ 0 pada 100 MHz (atau fallback §8.3) |
| 9 | Program HPS, uji board | Hasil sama dengan `sha256sum`; throughput terukur dicatat |

**Fase 5 (opsional):** (a) buffer pesan terpisah 16×32 agar host menulis blok berikut saat blok sekarang dihitung (≈ +256 ALM; manfaat besar bila bus lambat, hanya ±20% bila bus ideal); (b) `ERR` bila jumlah word WRAM yang ditulis kurang dari yang dibutuhkan (mask 16-bit); (c) Avalon master/DMA; (d) target `MSG_LEN` tidak berubah di tengah pesan sehingga `msg_len_q` bisa dihapus.

---

## 10. Integrasi Quartus / Platform Designer

* **Komponen:** buat `sha256_accelerator_hw.tcl` (atau pakai Component Editor) dengan: clock sink `clk`; reset sink `reset_n` (active-low, terasosiasi `clk`); Avalon-MM slave `s0` (alamat 6 bit, span 64 word = 256 byte; `addressUnits = WORDS`, `readLatency = 1`, `readWaitTime = 0`, `writeWaitTime = 0`, `associatedClock = clk`); interrupt sender `irq` (terasosiasi `clk` dan `s0`).
* **Clock:** satu PLL 100 MHz memberi `clk` akselerator dan input `h2f_lw_axi_clock` HPS, sehingga tidak perlu clock-crossing bridge *(verifikasi di versi Quartus yang dipakai)*.
* **Alamat:** sambungkan `h2f_lw_axi_master` → `s0`; pada Cyclone V HPS, lightweight bridge dipetakan di `0xFF200000` ditambah base komponen. Sambungkan `irq` ke `f2h_irq0`.
* **SDC (`sha256_soc.sdc`):**
```tcl
create_clock -name clk -period 10.000 [get_ports clk]
derive_pll_clocks
derive_clock_uncertainty
# Untuk kompilasi standalone (di luar Platform Designer) tambahkan virtual clock + set_input_delay/set_output_delay
# pada port avs_* agar jalur I/O tidak mendominasi laporan Fmax.
```
* **`build.tcl` (kerangka):**
```tcl
project_new sha256_soc -overwrite
set_global_assignment -name FAMILY "Cyclone V"
set_global_assignment -name DEVICE 5CSEBA6U23I7
set_global_assignment -name TOP_LEVEL_ENTITY sha256_accelerator
# sha256_defs.vh adalah include file, bukan modul; gunakan SEARCH_PATH dan `include
set_global_assignment -name SEARCH_PATH ../rtl
foreach f {k_rom.v wram.v pad_fn.v me.v mc.v hash_adder.v hram.v \
           sha256_fsm.v sha256_core.v sha256_csr.v sha256_accelerator.v} {
    set_global_assignment -name VERILOG_FILE ../rtl/$f
}
# k_rom.hex untuk $readmemh, atau gunakan `case` ROM inline agar tidak perlu file
set_global_assignment -name MIF_FILE ../rtl/k_rom.mif
set_global_assignment -name SDC_FILE sha256_soc.sdc
execute_flow -compile
project_close
```
*Catatan SDC:* dalam project Platform Designer clock sudah didaftarkan oleh `derive_pll_clocks`; perintah `create_clock` di SDC ini hanya untuk kompilasi **standalone** (di luar Platform Designer). Buat SDC bersyarat atau dua berkas SDC terpisah.

Laporkan dari hasil kompilasi: ALM, FF, M10K, DSP, Fmax (Timing Analyzer, model slow 85C/0C), dan slack setup/hold.

---

## 11. Keputusan Desain dan Asumsi (ubah bila tidak sesuai)

| # | Keputusan | Alasan | Alternatif |
|:-:|:---|:---|:---|
| 1 | Board **DE10-Nano** (SoC) | Avalon-MM + HPS hanya ada di varian SoC | Non-SoC: host = Nios II/master Avalon lain |
| 2 | Padding di FSM (rotasi 16 siklus), bukan di jalur tulis | Menghilangkan dummy write, urutan register kritis, dan kasus `len % 64 == 0` | Hapus Mode 1 pada rilis pertama |
| 3 | `LAST_BLK` hanya Mode 0 | Di Mode 1 hardware tahu kapan pesan berakhir dari `MSG_LEN` | — |
| 4 | Tanpa `waitrequest`; pelanggaran → `ERR` | Menyederhanakan bus dan timing | `waitrequest` saat BUSY |
| 5 | `BLOCK_CNT` menghitung setiap kompresi (termasuk otomatis) | Mudah diaudit terhadap jumlah blok sebenarnya | Hitung per START |
| 6 | `irq` juga naik untuk `ERR` | Host perlu tahu kesalahan protokol | Hanya `MSG_DONE` |
| 7 | `REG_ID` ditambahkan | Bring-up: memastikan alamat/bus benar | — |
| 8 | PAD menambah 16 siklus pada blok sisa | Murah (satu `pad_fn`, tanpa mux baca tambahan) | Masker paralel 1 siklus (+± 300 ALM) |
| 9 | Target Fmax 100 MHz dipertahankan | Konservatif untuk Cyclone V setelah `hkw` precompute | Lihat fallback §8.3 |
| 10 | Round engine **diturunkan** dari `project.v`, bukan ditulis ulang | Syarat hackathon (integrasi + modifikasi); ekuivalensi dibuktikan `tb_baseline_equiv` | Tulis ulang dari nol (tidak memenuhi syarat) |
| 11 | Legacy Step Mode (jendela `A..H,W,K` + `LEG_STEP`) dengan parameter `LEGACY_EN`, default 1 | Menjaga fungsi asli baseline, jalur uji ekuivalensi di board, bukti integrasi | `LEGACY_EN = 0`: hemat ≈ 66 FF dan ≈ 150–350 ALM; ekuivalensi hanya di simulasi |
| 12 | Pin wrapper Tiny Tapeout tidak dipakai di FPGA | Target Avalon-MM 32-bit; pin TT adalah 8-bit untuk ASIC | Wrapper tipis `tt_um_xeniarose_sha256` → `sha256_accelerator` (di luar lingkup v2) |
| 13 | `mc.v` mempertahankan reset async baseline | Perilaku identik dengan `project.v` | Hapus reset (hemat sedikit routing) |
| 14 | `MSG_LEN` 32-bit (maks 4 GiB − 1 byte); 29 bit atas `len_bits` selalu 0 | Hemat register dan jalur; SHA-256 pada FPGA umumnya tidak dipakai untuk pesan > 4 GiB | Lebarkan ke 61 bit bila perlu pesan > 4 GiB; akan mengubah `bytes_left`, `msg_len_q`, dan `len_bits` |

---

## 12. Integrasi dengan Baseline `tt07-sha256` (Syarat Hackathon)

Hackathon meminta **mengintegrasikan dan memodifikasi** baseline `tt07-sha256`. Bagian ini mengikat seluruh spesifikasi di atas ke baseline tersebut. Seluruh isi §12 adalah **addendum yang belum divalidasi model maupun RTL**; model Python dan testbench harus diperluas lebih dulu (§12.7).

### 12.1. Prinsip Integrasi

1. **`mc.v` harus diturunkan dari `project.v`** (salin lalu modifikasi), bukan ditulis ulang dari spesifikasi SHA-256. Persamaan round baseline dipertahankan; yang diubah hanya cara data masuk dan cara round dipicu (§4.6).
2. **Semua fitur v2 berfungsi sebagai penggerak round engine baseline** (tabel §12.5): K-ROM, WRAM + ME, FSM, `hkw`, `h_base`/HRAM/`hash_adder`, PAD, dan CSR/Avalon/IRQ masing-masing menggantikan pekerjaan yang di baseline dikerjakan host atau pin TT.
3. **Fungsi asli baseline tetap bisa dipakai** lewat Legacy Step Mode (§12.4) dan **dibuktikan identik** dengan testbench ekuivalensi (§12.6).
4. **Salinan asli baseline disimpan tak berubah** di `baseline/` (§6), dipakai untuk diff, bukti integrasi, dan acuan testbench.
5. **Lisensi.** `project.v` berlisensi Apache-2.0 (© 2024 xenia dragon). Pertahankan header SPDX/hak cipta pada berkas turunan (`mc.v`), tambahkan catatan bahwa berkas itu dimodifikasi beserta ringkasan perubahannya, dan sertakan berkas `LICENSE`. Ini ringkasan, bukan nasihat hukum; periksa teks lisensi dan aturan hackathon.

### 12.2. Hasil Analisis Baseline (dibaca dari `project.v`)

| Elemen | Isi di baseline |
|:---|:---|
| Modul / pin | `tt_um_xeniarose_sha256`; `ui_in[5:0]` = alamat, `ui_in[6]` = `io_we`, `ui_in[7]` = `io_clk`; `uio` = bus data 8-bit dua arah (`uio_oe = io_we`); `uo_out[0]` = `io_ready`, `uo_out[1]` = `io_we` |
| Register file | `register_file[9:0]`, 32-bit: indeks 0..7 = `A..H`, 8 = `W`, 9 = `K`; semua di-reset 0 (async) |
| Akses host | 1 byte per siklus `clk` bila `io_clk = 1`; indeks = `addr[5:2]`, byte lane = `addr[1:0]` (0 = bits 7:0, little-endian) |
| Round | tulis (`io_we = 0`) ke alamat **63**: `A<=temp1+temp2; B<=A; C<=B; D<=C; E<=D+temp1; F<=E; G<=F; H<=G` |
| Datapath | `s1 = Σ1(E)`, `ch`, `temp1 = H + s1 + ch + K + W`, `s0 = Σ0(A)`, `maj`, `temp2 = s0 + maj`; kombinasional, satu siklus |
| Baca | `io_we = 1`: `io_out <= 1 byte register_file[...]` (ter-register); alamat 63 → 0 |
| Tidak ada | message schedule, K-ROM, padding, akumulasi hash, status/interrupt selain `io_ready` |

**Kecocokan matematis (pembacaan kode):** rotasi pada `s1` (6, 11, 25) dan `s0` (2, 13, 22) serta `ch`, `maj`, dan urutan update `A..H` sama dengan definisi SHA-256 yang dipakai di §4.0. Ini hasil membaca kode, bukan simulasi; buktinya adalah T1 dan T2 di §12.6.

**Asal angka ≈ 640 siklus/blok (v1):** jika host menulis 1 byte per siklus, satu blok membutuhkan 8 register × 4 byte (muat `A..H`) + 64 round × (4 byte `W` + 4 byte `K` + 1 tulis alamat 63) + 8 register × 4 byte (baca `A..H`) = 32 + 576 + 32 = **640**. Ini batas bawah bus ideal, belum termasuk jadwal `W` dan penjumlahan akhir yang dikerjakan host. Angka ini harus diukur di T2, bukan diasumsikan.

**Keanehan baseline yang harus diperhitungkan:**

| # | Temuan | Aturan di turunan |
|:-:|:---|:---|
| 1 | `io_clk` adalah **enable level**, bukan edge: ditahan tinggi N siklus, operasi (termasuk round) diulang N kali | Jendela legacy dikemudikan strobe 1 siklus dari CSR; keanehan ini tidak diwarisi |
| 2 | Nama `io_we` terbalik secara fungsional: `io_we = 1` berarti **baca** (chip mengemudikan `uio`), `io_we = 0` berarti tulis | Jangan menyalin nama; pakai strobe tulis aktif-tinggi (`leg_we`) |
| 3 | Alamat 40..62 (indeks 10..15) di luar `register_file[9:0]`: tulis tak berefek, baca tak terdefinisi (X di simulasi) | Jendela legacy `0x2A–0x3F`: baca 0, tulis diabaikan |
| 4 | `` `default_nettype none `` ditetapkan di awal berkas dan tidak dipulihkan | Kompilasi `baseline/project.v` di **unit kompilasi terpisah** (file list terpisah di ModelSim/Questa, atau `vlog -work baseline_lib`); jangan satukan dalam satu daftar source dengan `mc.v`. Pastikan `mc.v` dimuat setelah `` `default_nettype wire `` sudah dipulihkan |
| 5 | Makro `` `A_reg `` … `` `K_reg `` didefinisikan global tanpa `` `undef `` | `mc.v` mempertahankan makro dan array `register_file` yang sama, tetapi menambahkan `` `undef `` di akhir berkas; jangan memakai nama makro itu di berkas lain. Dalam `tb_baseline_equiv.sv`, kompilasi `baseline/project.v` terlebih dahulu dalam unit terpisah, baru `mc.v` |

### 12.3. Peta Turunan (Traceability) dan Aturan Penyalinan

| Elemen baseline | Status | Lokasi di turunan |
|:---|:---|:---|
| `s1`, `ch`, `s0`, `maj`, `temp2` | **Dipakai apa adanya** (salin verbatim) | `mc.v` |
| Persamaan update `A..H` (isi `case 63`) | **Dipakai apa adanya**; pemicu diganti | `mc.v` (`round_en`) |
| `temp1 = H + s1 + ch + K + W` | **Dimodifikasi**: `H+K+W` menjadi register `hkw` (dijumlahkan satu siklus lebih awal), `temp1 = hkw + s1 + ch` | `mc.v` |
| `register_file[0..7]` (`A..H`) | **Dipakai** dengan array dan nama makro yang sama; ditambah jalur load dari `h_base` dan port tulis legacy | `mc.v` |
| `register_file[8]`, `[9]` (`W`, `K`) | **Dipertahankan** sebagai `W_reg`, `K_reg` untuk Legacy Step Mode; mode otomatis memakai WRAM/ME dan K-ROM | `mc.v` |
| Reset async seluruh register | **Dipertahankan** | `mc.v` |
| Pemicu round (tulis alamat 63) | **Diganti**: `round_en` dari FSM (64× per blok) atau `LEG_STEP` | `sha256_fsm.v`, `sha256_csr.v` |
| Antarmuka byte 8-bit TT (`ui_in`, `uio`, `uo_out`) | **Diganti**: Avalon-MM 32-bit; semantik lama tersedia lewat jendela legacy (word, bukan byte) | `sha256_csr.v` |
| `io_ready` | **Diganti**: `STATUS.BUSY/BLOCK_DONE`, `irq` | `sha256_csr.v` |
| Message schedule, K, padding, akumulasi hash | **Baru** (tidak ada di baseline) | `wram`, `me`, `k_rom`, `pad_fn`, `hram`, `hash_adder` |

**Langkah penyalinan `mc.v` (urut):**
1. Salin `baseline/project.v` ke `rtl/mc.v`; pertahankan header SPDX/hak cipta, tambahkan catatan "dimodifikasi: ..." di bawahnya.
2. Hapus port TT dan seluruh logika `io_*` (`io_addr`, `io_we`, `io_clk`, `io_ready`, `io_out`, `uio_*`, `uo_out`); ganti port list dengan §4.6.
3. Pertahankan **persis** ekspresi `s1`, `ch`, `s0`, `maj`, `temp2` dan isi `case 63`; ganti hanya pemicu dan operand `temp1`.
4. Pertahankan array `register_file[9:0]` dan makro `` `A_reg `` … `` `K_reg `` persis seperti `project.v`; tambahkan `` `undef `` di akhir berkas dan `` `default_nettype wire `` untuk memulihkan.
5. Tambahkan jalur `load`, `hkw`, dan port legacy (`[NEW]`).
6. Jalankan T1 (§12.6) sebelum memakai `mc.v` di mana pun; bila ada mismatch, perubahan terakhir di `mc.v` yang salah.

### 12.4. Legacy Step Mode (mempertahankan fungsi asli baseline)

**Tujuan:** (a) fungsi asli baseline ("tulis `A..H`, `W`, `K`, lalu picu satu round") tetap bisa dipakai host; (b) jalur uji ekuivalensi yang sama bisa dijalankan di board; (c) bukti bahwa round engine baseline benar-benar terintegrasi, bukan hanya ditiru.

**Parameter:** `LEGACY_EN` (default 1) pada `mc`, `sha256_fsm`, `sha256_core`, `sha256_csr`, dan top. Dengan `LEGACY_EN = 0` seluruh fitur ini hilang dan biaya area kembali ke angka v2 (§8); perbedaan hasil fitter antara 0 dan 1 adalah angka biaya integrasi.

**Antarmuka (perubahan §3):**
* `avs_address` menjadi 6 bit (64 word).
* **Jendela legacy** `0x20..0x29` (byte `0x80..0xA4`), R/W, word 32-bit penuh: word `i` = `register_file[i]` baseline → `A, B, C, D, E, F, G, H, W, K`. Alamat `0x2A..0x3F`: baca 0, tulis diabaikan, tanpa `ERR`.
* `REG_CTRL` bit 6 **`LEG_STEP`**: tulis 1 menjalankan **tepat satu round baseline** pada isi `A..H, W_reg, K_reg` saat ini. Self-clearing, hanya dievaluasi pada write itu.

**Aturan:**
* Tulis jendela legacy dan `LEG_STEP` hanya efektif saat tidak `BUSY`; pelanggaran → diabaikan + `ERR` (§3.4).
* `LEG_STEP` menyetel `BUSY` pada write itu, menghapus `BLOCK_DONE/MSG_DONE` (seperti `START`), dan selesai dengan `BLOCK_DONE` (tanpa `MSG_DONE`). `msg_active` dan `BLOCK_CNT` **tidak** berubah (bukan kompresi).
* Membaca jendela saat `BUSY` memberi snapshot register saat itu (berguna untuk debug round otomatis), bukan nilai atomik.
* `A..H` hanya dipakai sebagai scratch di antara pekerjaan; rantai multi-blok ada di HRAM dan `START` berikutnya selalu me-load ulang `A..H` dari `h_base`. Karena itu menulis jendela legacy di antara dua blok pesan tidak merusak digest (diuji di §12.6, T4).
* `SOFT_RST` tidak menghapus `A..H/W/K` (sama seperti HRAM/WRAM); hanya `reset_n` yang mereset.

**Urutan internal (FSM, dua state tambahan):**

| Siklus | State | Aksi |
|:-:|:---|:---|
| 0 | `IDLE` | melihat `leg_step_req` → `LPREP` (siklus keputusan) |
| 1 | `LPREP` | `leg_prep = 1`: `hkw <= H_reg + K_reg + W_reg` |
| 2 | `LRND` | `round_en = 1` (`shift_en = 0`): update `A..H` persis `case 63` baseline; `done_pulse` |

Total **3 siklus** (1 keputusan + 2) dari siklus keputusan hingga selesai; **belum diverifikasi model**. Tulis jendela legacy langsung diikuti `LEG_STEP` pada siklus berikutnya aman: `hkw` baru dihitung di `LPREP`, paling cepat dua tepi clock setelah tulis terakhir.

**Semantik:** satu `LEG_STEP` ≡ satu penulisan alamat 63 pada baseline. Isi `A..H` sesudahnya harus identik dengan baseline untuk `A..H, W, K` yang sama. Perbedaan hanya latensi (baseline 1 siklus, turunan 3 siklus) dan lebar akses (word 32-bit, bukan byte).

```c
// Padanan urutan baseline: tulis A..H, W, K, lalu picu satu round
for (i = 0; i < 10; i++) REG(LEG(i)) = val[i];     // A,B,C,D,E,F,G,H,W,K
REG(CTRL) = LEG_STEP;
if (wait_done()) { /* tangani error / timeout */ return -1; }  // pakai wait_done() dari §3.5
for (i = 0; i < 8; i++) out[i] = REG(LEG(i));      // A..H sesudah satu round
```

### 12.5. Fitur Plan sebagai Penggerak Round Engine Baseline

| Fitur di plan | Menggantikan pekerjaan baseline | Terhubung ke `mc.v` lewat |
|:---|:---|:---|
| `k_rom` | Host menulis `K_reg` setiap round | `k_val` → `hkw` |
| `wram` + `me` | Host menjadwalkan dan menulis `W_reg` setiap round | `w_n` → `hkw` |
| `sha256_fsm` | Host menulis alamat 63 sebanyak 64 kali | `load`, `round_en` |
| `hkw` (precompute) | Penjumlahan `H+K+W` di jalur kritis satu siklus | `temp1 = hkw + s1 + ch` |
| `h_base`, `hram`, `hash_adder` | Host menjumlahkan state akhir dengan hash sebelumnya | `h_base` → load; `state_out` → adder |
| `pad_fn` + state `PAD` | Host melakukan padding | tidak langsung (mengisi `wram`) |
| `sha256_csr` (Avalon, IRQ) | Pin TT 8-bit + `io_ready` | semua port kontrol `mc` |

### 12.6. Verifikasi Integrasi (wajib, tambahan atas §7)

| ID | Testbench | Isi | Lulus bila |
|:-:|:---|:---|:---|
| T1 | `tb_baseline_equiv.sv` | Instansiasi **`tt_um_xeniarose_sha256` asli** (`baseline/project.v`) dan `mc` (`LEGACY_EN = 1`) dalam satu TB. Stimulus acak identik: tulis `A..H, W, K` acak (baseline: 4 write byte per register; `mc`: `leg_we` per word), lalu satu round (baseline: tulis alamat 63; `mc`: `leg_prep` lalu `round_en`). Bandingkan `A..H` setelah tiap round (langsung `baseline.register_file[i]` vs `mc.register_file[i]`, karena nama sama). Sertakan rantai 64 round berurutan dan nilai ekstrem (0, `FFFFFFFF`) | ≥ 10.000 round, **0 mismatch** |
| T2 | `tb_baseline_driven.sv` | TB bertindak sebagai host baseline untuk `"abc"` dan blok acak: tulis IV ke `A..H`; tiap round tulis `W_t`, `K_t` (dari Python) lalu alamat 63; baca `A..H` setelah 64 round; TB menambahkan IV. Bandingkan dengan `hashlib` **dan** dengan digest akselerator (Mode 0) untuk blok yang sama. Catat siklus bus baseline dan siklus akselerator | Digest sama; angka siklus tercatat (pembanding sah: siklus, bukan Mhash/s) |
| T3 | `tb_accel_avalon.sv` (tambahan) | `LEG_STEP` dan jendela legacy lewat Avalon: urutan §12.4, `ERR` untuk tiga pelanggaran baru (§3.4), `BLOCK_DONE`/`BUSY`, 3 siklus | Sesuai spesifikasi |
| T4 | regresi | Seluruh §7.1 dan §7.2 dijalankan dua kali (`LEGACY_EN = 0` dan `1`); tulis jendela legacy di antara dua blok pesan multi-blok | Semua lolos; digest tidak berubah oleh tulis legacy |
| T5 | uji board | Program HPS menjalankan vektor T1 lewat `LEG_STEP`, golden dari `tools/baseline_ref.py` | Sama dengan golden |

### 12.7. Perubahan pada Model dan Dokumen

* `tools/baseline_ref.py`: transkripsi round `project.v` ke Python. Cek dirinya sendiri dengan menjalankan 64 round + IV lalu membandingkan dengan `hashlib`, supaya golden T1/T5 tidak berasal dari transkripsi yang salah.
* `sha256_arch_model.py`: tambahkan state `LPREP/LRND`, jendela legacy, dan assertion 3 siklus. Setelah dijalankan, perbarui Lampiran C.
* Header dan §8 sudah memuat angka dengan `LEGACY_EN = 1`; ganti dengan hasil fitter untuk kedua nilai parameter.

### 12.8. Batasan Integrasi

* Pin wrapper Tiny Tapeout (`ui_in`, `uio`, `uo_out`) **tidak dipakai** di target FPGA; yang dipakai ulang adalah round engine dan register file-nya. `baseline/project.v` hanya masuk simulasi, tidak masuk project Quartus (`build.tcl`). Bila juri mensyaratkan top-level tetap bernama `tt_um_xeniarose_sha256`, tambahkan wrapper tipis yang memetakan pin TT ke `sha256_accelerator`; ini di luar lingkup v2.
* Akses byte-lane baseline tidak didukung (Avalon tanpa `byteenable`); jendela legacy memakai word 32-bit.
* Klaim "memenuhi syarat integrasi" sebaiknya didukung tiga bukti: tabel §12.3, `diff baseline/project.v rtl/mc.v`, dan hasil T1/T2.

---

## Lampiran A. Konstanta K (`k_rom`), 64 × 32-bit

```text
428a2f98 71374491 b5c0fbcf e9b5dba5 3956c25b 59f111f1 923f82a4 ab1c5ed5
d807aa98 12835b01 243185be 550c7dc3 72be5d74 80deb1fe 9bdc06a7 c19bf174
e49b69c1 efbe4786 0fc19dc6 240ca1cc 2de92c6f 4a7484aa 5cb0a9dc 76f988da
983e5152 a831c66d b00327c8 bf597fc7 c6e00bf3 d5a79147 06ca6351 14292967
27b70a85 2e1b2138 4d2c6dfc 53380d13 650a7354 766a0abb 81c2c92e 92722c85
a2bfe8a1 a81a664b c24b8b70 c76c51a3 d192e819 d6990624 f40e3585 106aa070
19a4c116 1e376c08 2748774c 34b0bcb5 391c0cb3 4ed8aa4a 5b9cca4f 682e6ff3
748f82ee 78a5636f 84c87814 8cc70208 90befffa a4506ceb bef9a3f7 c67178f2
```
`K[0] = 428a2f98` ... `K[63] = c67178f2` (urutan baris demi baris, kiri ke kanan).

## Lampiran B. IV Awal (urutan A..H)
`6a09e667 bb67ae85 3c6ef372 a54ff53a 510e527f 9b05688c 1f83d9ab 5be0cd19`

## Lampiran C. Hasil Validasi Spesifikasi (model `sha256_arch_model.py`)

Model merepresentasikan: shift-register WRAM (tap `[0,1,9,14]`), K-ROM ter-register, `hkw` precompute, FSM 5 state, `PAD` rotasi 16 siklus, kelas `DATA/FULL_LAST/OVF/TAIL`, `second_pass`, `h_base = first_eff ? IV : HRAM`, aturan ERR. Hasil eksekusi:

```text
Vektor batas (0,3,55,56,63,64,65,119,120,128 B, NIST 56 B & 112 B): Mode 1 dan Mode 0 semuanya OK
Regresi acak: 1203 pesan (panjang 0..400 ×3) × 2 mode, berurutan tanpa reset: mismatch = 0
   (byte tak terpakai pada word parsial diisi acak; WRAM tidak dibersihkan antar pesan)
Siklus (assert ketat):  Mode 0 satu blok = 67   TAIL = 83   OVF (2 kompresi) = 165   FULL_LAST (2 kompresi) = 149
ERR: START tanpa FIRST_BLK saat idle -> ERR=1 ;  tulis WRAM saat BUSY -> ERR=1
NIST 1.000.000 x 'a': cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0  OK
TOTAL FAILS = 0
```

**Yang belum divalidasi:** seluruh addendum integrasi baseline (§12: ekuivalensi `mc.v` terhadap `project.v`, Legacy Step Mode, 3 siklus `LEG_STEP`), RTL Verilog, hasil sintesis/Fmax Quartus, perilaku Avalon di Platform Designer, dan uji board. **Cakupan model juga belum termasuk `MSG_LEN ≥ 2²⁹` — nilai `len_bits[63:32] ≠ 0` belum diuji; bug `cyc` pass-2 (§4.9) hanya muncul pada rentang ini.** Semua angka resource dan Fmax di §8 adalah perkiraan sampai ada laporan Quartus.
