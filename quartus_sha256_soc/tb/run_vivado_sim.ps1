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
# KONFIGURASI
# ============================================================
$VIVADO_BIN = "C:\AMDDesignTools\2025.2\Vivado\bin"
$ROOT       = Split-Path $PSScriptRoot -Parent
$RTL_DIR    = "$ROOT\rtl"
$TB_DIR     = "$ROOT\tb"
$WORK_DIR   = "$ROOT\xsim_work"

$xvlog = "$VIVADO_BIN\xvlog.bat"
$xelab = "$VIVADO_BIN\xelab.bat"
$xsim  = "$VIVADO_BIN\xsim.bat"

if (-not (Test-Path $xvlog)) {
    $xvlog = "xvlog"
    $xelab = "xelab"
    $xsim  = "xsim"
    Write-Host "[INFO] xvlog tidak ditemukan di $VIVADO_BIN, mencoba PATH..." -ForegroundColor Yellow
}

if (-not (Test-Path $WORK_DIR)) { New-Item -ItemType Directory -Path $WORK_DIR | Out-Null }
Push-Location $WORK_DIR

# ============================================================
# Daftar File
# ============================================================
$RTL_FILES = @(
    "$RTL_DIR\hash_adder.v", "$RTL_DIR\hram.v", "$RTL_DIR\k_rom.v", "$RTL_DIR\mc.v",
    "$RTL_DIR\me.v", "$RTL_DIR\pad_fn.v", "$RTL_DIR\sha256_fsm.v", "$RTL_DIR\wram.v"
)

$ALL_TB = @(
    "tb_unit_k_rom", "tb_unit_wram", "tb_unit_me", "tb_unit_hash_adder",
    "tb_unit_hram", "tb_unit_pad_fn", "tb_unit_mc", "tb_unit_sha256_fsm"
)

if ($TbName -eq "all") { $TB_LIST = $ALL_TB } else { $TB_LIST = @($TbName) }

# ============================================================
# Helper: cek apakah output tool mengandung error
# ============================================================
function Test-StepFailed {
    param([string]$Text)
    return ($LASTEXITCODE -ne 0) -or ($Text -match "(?m)^\s*ERROR:")
}

# ============================================================
# Fungsi Jalankan Testbench (mengembalikan $true / $false)
# ============================================================
function Run-Tb {
    param([string]$Name)

    Write-Host "`n============================================" -ForegroundColor Cyan
    Write-Host "  Menjalankan: $Name" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan

    $tb_file = "$TB_DIR\$Name.sv"
    if (-not (Test-Path $tb_file)) {
        Write-Host "[ERROR] File testbench tidak ditemukan: $tb_file" -ForegroundColor Red
        return $false
    }

    # Out-Host dipakai supaya output tool tampil di layar
    # tanpa ikut masuk ke nilai return fungsi.

    Write-Host "[1/4] Compile RTL..." -ForegroundColor Yellow
    $rtl_args = @("-sv", "--include", $RTL_DIR) + $RTL_FILES
    & $xvlog @rtl_args 2>&1 | Tee-Object -Variable rtl_out | Out-Host
    if (Test-StepFailed ($rtl_out | Out-String)) {
        Write-Host ">>> $Name : COMPILE RTL GAGAL" -ForegroundColor Red
        return $false
    }

    Write-Host "[2/4] Compile TB: $tb_file..." -ForegroundColor Yellow
    & $xvlog -sv --include $RTL_DIR $tb_file 2>&1 | Tee-Object -Variable tb_out | Out-Host
    if (Test-StepFailed ($tb_out | Out-String)) {
        Write-Host ">>> $Name : COMPILE TB GAGAL" -ForegroundColor Red
        return $false
    }

    Write-Host "[3/4] Elaborate..." -ForegroundColor Yellow
    & $xelab -debug typical $Name -s "${Name}_snap" 2>&1 | Tee-Object -Variable elab_out | Out-Host
    if (Test-StepFailed ($elab_out | Out-String)) {
        Write-Host ">>> $Name : ELABORATE GAGAL" -ForegroundColor Red
        return $false
    }

    Write-Host "[4/4] Simulate..." -ForegroundColor Yellow
    & $xsim "${Name}_snap" -runall 2>&1 | Tee-Object -Variable sim_out | Out-Host

    $output = $sim_out | Out-String
    if ($output -match "FAIL") {
        Write-Host ">>> $Name : FAIL" -ForegroundColor Red
        return $false
    } elseif ($output -match "PASS") {
        Write-Host ">>> $Name : PASS" -ForegroundColor Green
        return $true
    } else {
        Write-Host ">>> $Name : UNKNOWN (tidak ada kata PASS/FAIL di output)" -ForegroundColor Yellow
        return $false
    }
}

# ============================================================
# Eksekusi Utama
# ============================================================
Write-Host "`n============================================" -ForegroundColor Magenta
Write-Host " SHA-256 Unit Testbench Suite" -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta

$results = [ordered]@{}
foreach ($tbItem in $TB_LIST) {
    $results[$tbItem] = Run-Tb -Name $tbItem
}

Pop-Location

# ============================================================
# Ringkasan
# ============================================================
Write-Host "`n============================================" -ForegroundColor Magenta
Write-Host " RINGKASAN" -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta
foreach ($key in $results.Keys) {
    if ($results[$key]) {
        Write-Host ("  {0,-24} PASS" -f $key) -ForegroundColor Green
    } else {
        Write-Host ("  {0,-24} FAIL/ERROR" -f $key) -ForegroundColor Red
    }
}

if ($results.Values -contains $false) { exit 1 } else { exit 0 }