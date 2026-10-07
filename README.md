# Autonomous SHA-256 Hardware Accelerator (SoC Implementation)

This repository contains the RTL implementation, synthesis infrastructure, and simulation environment for an autonomous, low-area **SHA-256 Hardware Accelerator** targeting the **Intel Cyclone V SoC FPGA (DE10-Nano, `5CSEBA6U23I7`)**.

The design features an Avalon-MM Slave interface with HPS interrupt support, hardware auto-padding, multi-block message chaining, and an integrated iterative round computation engine.
![Designed Block Diagram](docs/Diagram%20blok.jpeg)
*Figure 1: Designed Block Diagram*

---

## 1. System Architecture

The accelerator consists of a hierarchical modular design:

* **`sha256_accelerator.v`** (Top-Level SoC Wrapper): Integrates Avalon-MM slave bus decoding, CSR registers, and interrupt generation with the computation core.
  * **`sha256_csr.v`**: Control, Status, and Configuration Registers interfacing with the CPU / HPS.
  * **`sha256_core.v`**: Main execution pipeline and datapath.
    * **`sha256_fsm.v`**: Multi-state controller coordinating `LOAD`, `ROUND`, `PAD`, and `FINALIZE` execution stages.
    * **`mc.v`**: Iterative round computation engine (derived from TT07 baseline).
    * **`me.v`**: Combinational on-the-fly Message Expansion ($\sigma_0, \sigma_1$).
    * **`wram.v`**: 16 × 32-bit shift register buffer for scheduled message words.
    * **`k_rom.v`**: 64 × 32-bit round constants mapped to embedded **M10K block RAM**.
    * **`hram.v`**: 256-bit register storing intermediate and final hash digests.
    * **`hash_adder.v`**: Modulo $2^{32}$ parallel adder computing $H_{i} = H_{i-1} + \text{Digest}$.
    * **`pad_fn.v`**: Combinational hardware auto-padding logic according to NIST FIPS 180-4.



---

## 2. Synthesis and Resource Utilization Tutorial

Synthesis and Place-and-Route (Fitting) can be performed either via the **Command-Line Interface (CLI)** or through the **Intel Quartus Prime GUI**.

### Method A: Automated Synthesis via Terminal (CLI)

The automated build script [`quartus_sha256_soc/quartus/build.tcl`](quartus_sha256_soc/quartus/build.tcl) sets up the target device, assigns constraints, adds all RTL sources, and runs the entire compilation flow.

1. Open PowerShell or Command Prompt and navigate to the project quartus directory:
   ```powershell
   cd quartus_sha256_soc\quartus
   ```

2. Execute the build script using the Quartus Shell executable:
   * **Using Quartus II 13.1:**
     ```powershell
     & "C:\altera\13.1\quartus\bin64\quartus_sh.exe" -t build.tcl
     ```
   * **Using Quartus Prime (18.1+):**
     ```powershell
     & "C:\intelFPGA\18.1\quartus\bin64\quartus_sh.exe" -t build.tcl
     ```
   *(Alternatively, if `quartus_sh` is in your system `PATH`, simply run `quartus_sh -t build.tcl`).*

3. **Inspect Resource Utilization via Generated Reports:**  
   Once compilation completes, view the generated summary files in the `output_files/` directory:
   * **`output_files/sha256_soc.fit.summary`**: Displays chip-level summary metrics (ALMs, registers, memory blocks, DSPs, pins).
   * **`output_files/sha256_soc.map.rpt`**: Look under section **`Analysis & Synthesis Resource Utilization by Entity`** for a full breakdown of resources per submodule.
   * **`output_files/sha256_soc.sta.summary`**: Contains timing slack verification against the 100 MHz target clock.

---

### Method B: Interactive Synthesis via Intel Quartus Prime GUI

1. **Open the Project:**
   * Launch **Intel Quartus Prime** (or **Quartus II**).
   * Go to **File** $\rightarrow$ **Open Project...**
   * Select `quartus_sha256_soc/quartus/sha256_soc.qpf`.

2. **Execute Compilation:**
   * In the top menu, navigate to **Processing** $\rightarrow$ **Start Compilation** (or press `Ctrl + L`).
   * Alternatively, to perform synthesis only without fitting, select **Processing** $\rightarrow$ **Start** $\rightarrow$ **Start Analysis & Synthesis** (`Ctrl + K`).

3. **Inspect Resource Reports:**
   * Open the **Compilation Report** window via **Processing** $\rightarrow$ **Compilation Report** (or press `Ctrl + R`).
   * **Top-Level Summary:** Click on **Flow Summary** in the left panel to examine total ALMs, dedicated registers, memory bits, and DSP blocks.
   * **Hierarchical Submodule Breakdown:** Expand **Analysis & Synthesis** (or **Fitter** $\rightarrow$ **Resource Section**) and select **Resource Utilization by Entity**. This displays an interactive tree table showing logic and register allocations for each individual module (`u_mc`, `u_wram`, `u_hram`, etc.).
   * **Timing Performance:** Expand **TimeQuest Timing Analyzer** $\rightarrow$ **Multicorner Timing Analysis Summary** to verify setup/hold slacks and maximum frequency ($F_{max}$).

4. **Visualizing the Hardware Schematic (Optional):**
   * Double-click **Tools** $\rightarrow$ **Netlist Viewers** $\rightarrow$ **RTL Viewer** to view the synthesized gate- and block-level hardware schematic.

![Quartus RTL Design](docs/Quartus%20RTL%20Design.jpeg)
*Figure 1: Synthesized top-level RTL schematic showing core and bus controller interconnection.*

---

## 3. Implementation & Synthesis Results

Target Device: **Cyclone V 5CSEBA6U23I7**  
Toolchain: **Intel Quartus II 64-Bit Version 13.1.0 Web Edition**

![Analysis & Synthesis Resource Usage Summary](docs/Resource%20usage%20summary.jpeg)
*Figure 2: Analysis & Synthesis resource usage summary in Intel Quartus II.*

### 3.1. Overall Resource Utilization

![Compilation Flow Summary Report](docs/Compilation%20report.jpeg)
*Figure 3: Full compilation flow summary and Fitter resource report for Cyclone V.*

| Metric | Utilized | Total Available | Utilization (%) |
| :--- | :---: | :---: | :---: |
| **Logic Utilization (ALMs)** | **1,366** | 41,910 | **3 %** |
| **Combinational ALUTs** | **1,582** | 83,820 | **2 %** |
| **Dedicated Logic Registers (FF)** | **1,562** | 83,820 | **2 %** |
| **Total Block Memory Bits** | **2,048** | 5,662,720 | **< 1 %** (1 × M10K) |
| **DSP Blocks** | **0** | 112 | **0 %** |
| **I/O Pins** | **75** | 314 | **24 %** |
| **Clock Constraint ($F_{target}$)** | **100.0 MHz** (10.0 ns) | - | - |
| **Worst-Case Slack** | **+1.487 ns** | - | **Passed ($F_{max} \approx 117.4\text{ MHz}$)** |

### 3.2. Hierarchical Resource Utilization by Entity

| Hierarchy / Module | Combinational ALUTs | Dedicated Registers | M10K Memory Bits | DSP Blocks | Description |
| :--- | :---: | :---: | :---: | :---: | :--- |
| **`sha256_accelerator`** | **1,582** | **1,418** | **2,048** | **0** | **Top-Level Entity** |
| ├── `u_csr` (`sha256_csr`) | 310 | 184 | 0 | 0 | Avalon bus interface & control registers |
| └── `u_core` (`sha256_core`) | 1,272 | 1,234 | 2,048 | 0 | SHA-256 Core Top |
| &emsp;&emsp;├── `u_mc` (`mc`) | 663 | 352 | 0 | 0 | Baseline round calculation engine |
| &emsp;&emsp;├── `u_wram` (`wram`) | 58 | 512 | 0 | 0 | 16 × 32-bit shift register buffer |
| &emsp;&emsp;├── `u_hram` (`hram`) | 0 | 256 | 0 | 0 | 8 × 32-bit hash digest registers |
| &emsp;&emsp;├── `u_hadder` (`hash_adder`) | 256 | 0 | 0 | 0 | Modulo $2^{32}$ final hash accumulators |
| &emsp;&emsp;├── `u_fsm` (`sha256_fsm`) | 152 | 114 | 0 | 0 | Sequencing & auto-pad controller |
| &emsp;&emsp;├── `u_me` (`me`) | 128 | 0 | 0 | 0 | Message expansion combinational logic |
| &emsp;&emsp;├── `u_pad` (`pad_fn`) | 15 | 0 | 0 | 0 | Auto-padding vector generation |
| &emsp;&emsp;└── `u_krom` (`k_rom`) | 0 | 0 | 2,048 | 0 | 64 × 32-bit constants in 1 M10K RAM |

---

## 4. Directory Structure

```text
PERURI/
├── .gitignore                          # Git ignore rules for Quartus / EDA artifacts
├── README.md                           # Project documentation & synthesis tutorial
├── implementation_plan_revised_v2.md   # Architectural specification document
└── quartus_sha256_soc/
    ├── baseline/                       # Reference tt07-sha256 baseline design
    ├── quartus/
    │   ├── build.tcl                   # Automated Quartus compilation Tcl script
    │   ├── sha256_soc.sdc              # Timing constraint specifications
    │   ├── sha256_soc.qpf              # Quartus Project File
    │   ├── sha256_soc.qsf              # Quartus Settings File
    │   └── output_files/               # Synthesis, fitting, and timing reports
    ├── rtl/                            # Synthesizable Verilog HDL sources
    ├── sw/                             # Bare-metal / HPS software drivers
    ├── tb/                             # SystemVerilog testbenches & simulation scripts
    └── tools/                          # Python architectural verification models
```

---

## 5. References

* [ttsky-verilog-sha256-processor](https://github.com/dvirdc/ttsky-verilog-sha256-processor)
* [secworks/sha256](https://github.com/secworks/sha256)
* [tharunchitipolu/SHA-256-Verilog-HDL](https://github.com/tharunchitipolu/SHA-256-Verilog-HDL)
* [rnz/verilog-sha256](https://github.com/rnz/verilog-sha256)
