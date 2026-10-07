// SPDX-FileCopyrightText: Copyright (c) 2026 Peruri
// SPDX-License-Identifier: Apache-2.0
//
// test_sha256.c — HPS test program for SHA-256 Accelerator
// Runs on ARM Cortex-A9 (DE10-Nano), maps lightweight HPS-FPGA bridge.
// Compares results with OpenSSL SHA-256, measures throughput.

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>

// ---- Lightweight HPS-to-FPGA Bridge base address ----
#define LW_BRIDGE_BASE  0xFF200000UL
#define LW_BRIDGE_SPAN  0x00200000UL

// ---- Accelerator base offset within bridge (adjust to match Platform Designer) ----
#define SHA256_BASE_OFFSET  0x00000000UL

// ---- Register offsets (word addresses × 4) ----
#define REG_CTRL        (sha256_base + 0x00)
#define REG_STATUS      (sha256_base + 0x04)
#define REG_BLOCK_CNT   (sha256_base + 0x08)
#define REG_MSG_LEN     (sha256_base + 0x0C)
#define REG_WRAM(i)     (sha256_base + 0x10 + (i)*4)
#define REG_DIGEST(i)   (sha256_base + 0x50 + (i)*4)
#define REG_ID          (sha256_base + 0x70)
#define REG_IRQ_MASK    (sha256_base + 0x74)
#define REG_LEG(i)      (sha256_base + 0x80 + (i)*4)

// ---- CTRL bits ----
#define CTRL_START      (1u << 0)
#define CTRL_SOFT_RST   (1u << 1)
#define CTRL_FIRST_BLK  (1u << 2)
#define CTRL_LAST_BLK   (1u << 3)
#define CTRL_AUTO_PAD   (1u << 5)
#define CTRL_LEG_STEP   (1u << 6)

// ---- STATUS bits ----
#define STATUS_BUSY         (1u << 0)
#define STATUS_BLOCK_DONE   (1u << 1)
#define STATUS_MSG_DONE     (1u << 2)
#define STATUS_ERR          (1u << 3)
#define STATUS_MSG_ACTIVE   (1u << 4)

#define POLL_TIMEOUT 1000000UL

// ---- Global pointer to accelerator registers ----
static volatile uint32_t *sha256_base;
static void *lw_bridge_virt;
static int mem_fd = -1;

// ---- Memory-mapped I/O helpers ----
static inline uint32_t rd(volatile uint32_t *reg)  { return *reg; }
static inline void      wr(volatile uint32_t *reg, uint32_t v) { *reg = v; }

// ---- Map HPS-FPGA bridge ----
static int map_bridge(void) {
    mem_fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (mem_fd < 0) { perror("open /dev/mem"); return -1; }

    lw_bridge_virt = mmap(NULL, LW_BRIDGE_SPAN, PROT_READ | PROT_WRITE,
                          MAP_SHARED, mem_fd, LW_BRIDGE_BASE);
    if (lw_bridge_virt == MAP_FAILED) { perror("mmap"); return -1; }

    sha256_base = (volatile uint32_t *)((uint8_t *)lw_bridge_virt + SHA256_BASE_OFFSET);
    return 0;
}

static void unmap_bridge(void) {
    if (lw_bridge_virt != MAP_FAILED)
        munmap(lw_bridge_virt, LW_BRIDGE_SPAN);
    if (mem_fd >= 0)
        close(mem_fd);
}

// ---- Poll until BLOCK_DONE or timeout ----
static int wait_done(void) {
    for (uint32_t t = 0; t < POLL_TIMEOUT; t++) {
        uint32_t s = rd(REG_STATUS);
        if (s & STATUS_ERR)      { printf("ERR: status=0x%08x\n", s); return -1; }
        if (s & STATUS_BLOCK_DONE) return 0;
    }
    printf("TIMEOUT\n");
    return -2;
}

// ---- big-endian word from 4 bytes ----
static uint32_t be32(const uint8_t *p, size_t n_avail) {
    uint8_t buf[4] = {0};
    size_t copy = n_avail < 4 ? n_avail : 4;
    memcpy(buf, p, copy);
    return ((uint32_t)buf[0] << 24) | ((uint32_t)buf[1] << 16) |
           ((uint32_t)buf[2] <<  8) |  (uint32_t)buf[3];
}

// ---- Soft reset ----
static void soft_reset(void) {
    wr(REG_CTRL, CTRL_SOFT_RST);
    wr(REG_STATUS, STATUS_BLOCK_DONE | STATUS_MSG_DONE | STATUS_ERR);
}

// ---- Mode 1: Hash using hardware auto-padding ----
static int sha256_hw_mode1(const uint8_t *msg, size_t len,
                            uint8_t digest_out[32]) {
    wr(REG_MSG_LEN, (uint32_t)len);

    size_t off = 0;
    size_t rem = len;
    int first  = 1;

    do {
        size_t n = rem < 64 ? rem : 64;
        size_t nw = (n + 3) / 4;

        for (size_t i = 0; i < nw; i++) {
            size_t avail = (off + 4*i + 4 <= len) ? 4 : len - (off + 4*i);
            wr(REG_WRAM(i), be32(msg + off + 4*i, avail));
        }

        uint32_t ctrl = CTRL_START | CTRL_AUTO_PAD | (first ? CTRL_FIRST_BLK : 0);
        wr(REG_CTRL, ctrl);

        if (wait_done()) {
            wr(REG_STATUS, STATUS_ERR);
            soft_reset();
            return -1;
        }
        // W1C BLOCK_DONE
        wr(REG_STATUS, STATUS_BLOCK_DONE);

        off  += n;
        rem  -= n;
        first = 0;

    } while (!(rd(REG_STATUS) & STATUS_MSG_DONE));

    // W1C MSG_DONE
    wr(REG_STATUS, STATUS_MSG_DONE);

    // Read digest (big-endian words → bytes)
    for (int i = 0; i < 8; i++) {
        uint32_t w = rd(REG_DIGEST(i));
        digest_out[4*i+0] = (w >> 24) & 0xFF;
        digest_out[4*i+1] = (w >> 16) & 0xFF;
        digest_out[4*i+2] = (w >>  8) & 0xFF;
        digest_out[4*i+3] =  w        & 0xFF;
    }
    return 0;
}

// ---- Simple hex print ----
static void print_hex(const char *label, const uint8_t *data, size_t len) {
    printf("%s: ", label);
    for (size_t i = 0; i < len; i++) printf("%02x", data[i]);
    printf("\n");
}

// ---- Bring-up check ----
static int bringup_check(void) {
    uint32_t id = rd(REG_ID);
    printf("REG_ID = 0x%08x  (expected 0x53484132 'SHA2')\n", id);
    if (id != 0x53484132u) {
        printf("ERROR: REG_ID mismatch — check base address or Quartus build\n");
        return -1;
    }
    printf("Bring-up: OK\n");
    return 0;
}

// ---- Main ----
int main(void) {
    printf("=== SHA-256 Accelerator Board Test ===\n");
    printf("Platform: DE10-Nano (Cyclone V SoC)\n\n");

    if (map_bridge() != 0) return 1;

    soft_reset();

    if (bringup_check() != 0) { unmap_bridge(); return 1; }

    // Test vectors
    typedef struct {
        const char  *name;
        const char  *msg;
        const char  *expected_hex;
    } tv_t;

    static const tv_t tvs[] = {
        {"empty",   "",    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},
        {"abc",     "abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"},
        {"55a",     NULL,  "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318"},
        {"64a",     NULL,  "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb"},
    };

    // Build 55 and 64 'a' buffers
    static uint8_t buf55[55], buf64[64];
    memset(buf55, 'a', sizeof(buf55));
    memset(buf64, 'a', sizeof(buf64));

    int total_fail = 0;

    for (int t = 0; t < 4; t++) {
        const tv_t *tv = &tvs[t];
        const uint8_t *msg;
        size_t          len;

        if (t == 0)      { msg = (const uint8_t *)""; len = 0; }
        else if (t == 1) { msg = (const uint8_t *)"abc"; len = 3; }
        else if (t == 2) { msg = buf55; len = 55; }
        else             { msg = buf64; len = 64; }

        uint8_t digest[32];
        struct timespec t0, t1;

        soft_reset();
        clock_gettime(CLOCK_MONOTONIC, &t0);
        if (sha256_hw_mode1(msg, len, digest) != 0) {
            printf("[%s] ERROR\n", tv->name);
            total_fail++;
            continue;
        }
        clock_gettime(CLOCK_MONOTONIC, &t1);
        long elapsed_ns = (t1.tv_sec - t0.tv_sec) * 1000000000L +
                          (t1.tv_nsec - t0.tv_nsec);

        // Convert digest to hex string
        char got_hex[65];
        for (int i = 0; i < 32; i++) sprintf(got_hex + 2*i, "%02x", digest[i]);
        got_hex[64] = 0;

        int ok = (strcmp(got_hex, tv->expected_hex) == 0);
        printf("[%s] %s  time=%ld ns  digest=%s\n",
               tv->name, ok ? "PASS" : "FAIL", elapsed_ns, got_hex);
        if (!ok) {
            printf("  expected: %s\n", tv->expected_hex);
            total_fail++;
        }
    }

    // Throughput benchmark: 1000 × "abc"
    printf("\n=== Throughput benchmark (1000 × 'abc') ===\n");
    struct timespec tb0, tb1;
    clock_gettime(CLOCK_MONOTONIC, &tb0);
    for (int i = 0; i < 1000; i++) {
        uint8_t d[32];
        soft_reset();
        sha256_hw_mode1((const uint8_t *)"abc", 3, d);
    }
    clock_gettime(CLOCK_MONOTONIC, &tb1);
    long bench_ns = (tb1.tv_sec - tb0.tv_sec) * 1000000000L +
                    (tb1.tv_nsec - tb0.tv_nsec);
    printf("  1000 hashes: %ld ms  (%.1f hashes/s)\n",
           bench_ns / 1000000, 1e9 * 1000 / (double)bench_ns);
    printf("  Per-hash: %ld ns\n", bench_ns / 1000);

    printf("\n=== TOTAL: %d failure(s) ===\n", total_fail);

    unmap_bridge();
    return total_fail ? 1 : 0;
}
