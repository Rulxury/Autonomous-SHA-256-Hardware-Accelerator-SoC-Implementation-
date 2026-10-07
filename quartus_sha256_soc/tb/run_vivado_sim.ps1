# SPDX-FileCopyrightText: Copyright (c) 2026 Peruri
# SPDX-License-Identifier: Apache-2.0
#
# run_vivado_sim.ps1 — Script PowerShell untuk menjalankan unit testbench di Vivado xsim
# Jalankan: .\tb\run_vivado_sim.ps1
# Pastikan Vivado ada di PATH atau edit $VIVADO_BIN di bawah

param(
    [string]$TbName = "all"  # "all" atau nama spesifik, contoh: "tb_unit_k_rom"
)

# ============================================================
# KONFIGURASI — sesuaikan path Vivado jika perlu
# ============================================================
$VIVADO_BIN = "C:\Xilinx\Vivado\2023.2\bin"    # ganti sesuai versi kamu
$ROOT       = Split-Path $PSScriptRoot -Parent
$RTL        = "$ROOT\rtl"
$TB         = "$ROOT\tb"
$WORK_DIR   = "$ROOT\xsim_work"

# Cek apakah xvlog ada
$xvlog = "$VIVADO_BIN\xvlog.bat"
$xelab = "$VIVADO_BIN\xelab.bat"
$xsim  = "$VIVADO_BIN\xsim.bat"

if (-not (Test-Path $xvlog)) {
    # Coba cari di PATH
    $xvlog = "xvlog"
    $xelab = "xelab"
    $xsim  = "xsim"
    Write-Host "[INFO] xvlog tidak ditemukan di $VIVADO_BIN, mencoba PATH..." -ForegroundColor Yellow
}

# Buat work dir
if (-not (Test-Path $WORK_DIR)) { New-Item -ItemType Directory -Path $WORK_DIR | Out-Null }
Push-Location $WORK_DIR

# ============================================================
# Daftar file RTL
# ============================================================
$RTL_FILES = @(
    "$RTL\hash_adder.v",
    "$RTL\hram.v",
    "$RTL\k_rom.v",
    "$RTL\mc.v",
    "$RTL\me.v",
    "$RTL\pad_fn.v",
    "$RTL\sha256_fsm.v",
    "$RTL\wram.v"
)

# ============================================================
# Daftar testbench
# ============================================================
$ALL_TB = @(
    "tb_unit_k_rom",
    "tb_unit_wram",
    "tb_unit_me",
    "tb_unit_hash_adder",
    "tb_unit_hram",
    "tb_unit_pad_fn",
    "tb_unit_mc",
    "tb_unit_sha256_fsm"
)

# Pilih testbench yang dijalankan
if ($TbName -eq "all") {
    $TB_LIST = $ALL_TB
} else {
    $TB_LIST = @($TbName)
}

# ============================================================
# Fungsi jalankan satu testbench
# ============================================================
function Run-Tb {
    param([string]$Name)

    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  Menjalankan: $Name" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan

    # Step 1: Compile RTL
    $rtl_args = @("-sv", "--incdir", $RTL) + $RTL_FILES
    Write-Host "[1/3] Compile RTL..." -ForegroundColor Yellow
    & $xvlog @rtl_args 2>&1 | Tee-Object -Variable rtl_out
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        Write-Host "GAGAL compile RTL (kode $LASTEXITCODE)" -ForegroundColor Red
        return $false
    }

    # Step 2: Compile testbench
    $tb_file = "$TB\$Name.sv"
    Write-Host "[2/3] Compile TB: $tb_file..." -ForegroundColor Yellow
    & $xvlog -sv "--incdir" $RTL $tb_file 2>&1 | Tee-Object -Variable tb_out
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        Write-Host "GAGAL compile TB (kode $LASTEXITCODE)" -ForegroundColor Red
        return $false
    }

    # Step 3: Elaborate
    Write-Host "[3/3] Elaborate..." -ForegroundColor Yellow
    & $xelab -debug "typical" $Name "-s" "${Name}_snap" 2>&1 | Tee-Object -Variable elab_out
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        Write-Host "GAGAL elaborate (kode $LASTEXITCODE)" -ForegroundColor Red
        return $false
    }

    # Step 4: Simulate
    Write-Host "[4/4] Simulate..." -ForegroundColor Yellow
    & $xsim "${Name}_snap" -runall 2>&1 | Tee-Object -Variable sim_out

    # Cek PASS/FAIL
    $output = $sim_out -join "`n"
    if ($output -match "PASS") {
        Write-Host ">>> $Name : PASS" -ForegroundColor Green
        return $true
    } elseif ($output -match "FAIL") {
        Write-Host ">>> $Name : FAIL" -ForegroundColor Red
        return $false
    } else {
        Write-Host ">>> $Name : UNKNOWN (cek output manual)" -ForegroundColor Yellow
        return $false
    }
}

# ============================================================
# Jalankan semua testbench
# ============================================================
Write-Host ""
Write-Host "============================================" -ForegroundColor Magenta
Write-Host " SHA-256 Unit Testbench Suite — Vivado xsim" -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta

$pass_count = 0
$fail_count = 0
$results = @{}

foreach ($tb in $TB_LIST) {
    $ok = Run-Tb -Name $tb
    if ($ok) {
        $pass_count++
        $results[$tb] = "PASS"
    } else {
        $fail_count++
        $results[$tb] = "FAIL"
    }
}

# ============================================================
# Ringkasan
# ============================================================
Write-Host ""
Write-Host "============================================" -ForegroundColor Magenta
Write-Host " RINGKASAN HASIL" -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta
foreach ($tb in $TB_LIST) {
    $status = $results[$tb]
    if ($status -eq "PASS") {
        Write-Host "  ✓ $tb" -ForegroundColor Green
    } else {
        Write-Host "  ✗ $tb" -ForegroundColor Red
    }
}
Write-Host ""
Write-Host "  PASS: $pass_count / $($pass_count + $fail_count)" -ForegroundColor White
if ($fail_count -eq 0) {
    Write-Host "  Semua testbench LULUS!" -ForegroundColor Green
} else {
    Write-Host "  $fail_count testbench GAGAL — periksa output di atas" -ForegroundColor Red
}

Pop-Location
