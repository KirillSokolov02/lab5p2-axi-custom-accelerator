# Lab5p2 — AXI Custom Accelerator with Cross-Domain Handshake Synchronization

A **Zynq-7000 FPGA project** implementing a **custom AXI accelerator IP** that computes `a*b + c*d` on four 8-bit values. The design features **dual-clock-domain synchronization** using handshake protocols, demonstrating real-world techniques for crossing clock boundaries in FPGA systems.

## Overview

This project implements a hardware accelerator for the arithmetic expression:

    result = a*b + c*d

where a, b, c, and d are each 8-bit unsigned values, packed into 32-bit input words. The accelerator receives input data from a Zynq-7000 Processing System via an AXI Lite interface, processes the data in a separate clock domain, and writes results back through memory.

The key architectural feature is the **dual-clock-domain handshake synchronizer**, which safely transfers data between two independent clock domains without metastability issues.

## Architecture

The system uses a **two-clock-domain architecture**:

- **Clock Domain 1 (100 MHz)** — Zynq PS clock, handles AXI communication, memory management, and I/O
- **Clock Domain 2 (user-defined)** — Accelerator clock, performs the actual computation

Data flows from the PS through AXI into Domain 1, crosses into Domain 2 via handshake synchronizers, is processed by the datapath, crosses back via another handshake pair, and is written to output memory for the PS to read.

### Accelerator Pipeline

The accelerator processes 4 independent 8-bit values per 32-bit word:
1. Pack four 8-bit values into a 32-bit word at the input memory
2. The datapath splits them into pairs and computes two multiplications in parallel
3. Results are summed: `(a*b) + (c*d)` producing a 17-bit result (8-bit * 8-bit = 16-bit max, two of them summed = up to 17 bits)
4. The result is written to the output memory

## Component Breakdown

### Accelerator Entity (`accelerator_v1_0.vhd`)

Top-level AXI IP wrapper that instantiates:
- **AXI Lite interface** (`accelerator_v1_0_S00_AXI.vhd`) — 32-bit data, 20-bit address
- **Clock domain crossing** — `clk2` input for the second clock domain
- **User logic integration** — connects the datapath and handshake synchronizers

### Memory Map (`memory_map.vhd`)

Registers and address decode logic providing software-accessible control:

| Address | Register | Access | Purpose |
|---------|----------|--------|---------|
| Base + 0x00 | GO | Write | Launch computation |
| Base + 0x04 | SIZE | Read/Write | Number of input words to process |
| Base + 0x0C | DONE | Read | Computation status flag |
| Base + 0x00–0x7FFF | Input Memory | Write | Pack 4x 8-bit values per 32-bit word |
| Base + 0x00–0x7FFF | Output Memory | Read | 17-bit results packed in 32-bit words |

### User Application (`user_app.vhd`)

Top-level integration entity that connects all components:

1. **Memory controller** — handles AXI reads/writes to registers and BRAM
2. **Input BRAM** — stores input data (2^15 = 32K words, 32-bit wide)
3. **Address generator (input)** — reads from input BRAM sequentially
4. **Handshake synchronizer (in)** — crosses from Domain 1 to Domain 2
5. **Datapath** — performs `a*b + c*d` computation
6. **Output register** — holds datapath result until read by Domain 1
7. **Handshake synchronizer (out)** — crosses from Domain 2 back to Domain 1
8. **Address generator (output)** — writes results to output BRAM

### Datapath (`datapath.vhd`)

Computes `a*b + c*d` in a single clock cycle:

```
input[31:24] = a, input[23:16] = b, input[15:8] = c, input[7:0] = d
reg_mult0 = a * b          (16-bit)
reg_mult1 = c * d          (16-bit)
result = reg_mult0 + reg_mult1  (17-bit)
```

A 3-cycle delay element provides pipeline synchronization for the valid signal.

### Handshake Synchronizer (`handshake.vhd`)

Cross-domain synchronizer using request/acknowledge protocol:
- **go** signal from source domain triggers data transfer
- **rcv** signal in destination domain confirms data received
- **ack** signal back to source domain confirms round-trip complete
- **delay_ack** provides timing margin for data setup

### Configuration Packages

**config_pkg.vhd** — Global configuration constants:
- 18-bit memory-mapped address width (256 KB address space)
- 32-bit data width
- 4 clock domains (though only 2 are actively used)

**user_pkg.vhd** — User-specific parameters:
- 15-bit data memory address width (32K words)
- 32-bit input width, 17-bit output width
- Memory range: 0x00000 to 0x7FFF (32K words)
- Register addresses: GO at 0x8000, SIZE at 0xC000, DONE at 0xFFFF

### Zynq Processing System (`design_1_wrapper.vhd`)

Top-level block design wrapper connecting:
- **PS7** — ARM Cortex-A9 dual-core processor
- **DDR** — 32-bit DDR memory interface (15 address bits)
- **AXI Interconnect** — routes PS to accelerator and memory
- **Clock Wizard** — generates secondary clock for accelerator domain
- **Reset Controller** — stable reset for all domains
- **sys_clock** — 100 MHz board clock input

## Zynq-7000 Configuration

| Parameter | Value |
|-----------|-------|
| **Part** | xc7z020clg484-1 |
| **Family** | Zynq-7000 (Artix-7 + ARM Cortex-A9) |
| **Package** | CLG484 |
| **Speed Grade** | -1 |
| **Vivado Version** | 2021.1 |
| **Top-Level** | design_1_wrapper (Block Design) |

### Clock Domains

| Domain | Frequency | Purpose |
|--------|-----------|---------|
| **clk[0]** | 100 MHz (PS clock) | AXI interface, memory controller |
| **clk[1]** | User-defined | Accelerator datapath |
| **clk[2]** | — | Reserved |
| **clk[3]** | — | Reserved |

## Memory Organization

The accelerator maps both registers and memory into a single 256 KB address space (18-bit addressing):

```
0x00000 — 0x7FFFF : Input/Output BRAM (32K words shared)
0x80000 : GO register (write to launch)
0xC0000 : SIZE register (read/write number of words)
0xFFFFC : DONE register (read for completion status)
```

### BRAM Configuration

| Parameter | Value |
|-----------|-------|
| **Capacity** | 2^15 = 32,768 words |
| **Width** | 32-bit input, 17-bit output |
| **Access** | Synchronous read/write |
| **Reset** | All zeros |

## VHDL Conventions

- **IEEE 1164** — Standard logic types
- **IEEE numeric_std** — Unsigned arithmetic with explicit resizing
- **Generic Map** — Configurable BRAM sizes and data widths
- **Entity-Architecture** — Clean interface separation
- **Signal Naming** — Descriptive names following UF convention

### Arithmetic Safety

The 17-bit output width is intentionally chosen to prevent overflow:
- Maximum intermediate product: 255 * 255 = 65,025 (16 bits)
- Maximum sum: 65,025 + 65,025 = 130,051 (17 bits)

## Design Methodology

### Cross-Clock-Domain (CDC) Technique

This project uses **request/acknowledge handshake** for clock domain crossing instead of simpler techniques like FIFOs or synchronizer chains. This approach:

1. **Guarantees no data loss** — every transfer is acknowledged before the next begins
2. **Prevents metastability** — the handshake synchronizer uses multi-stage flip-flops
3. **Provides back-pressure** — the source cannot send until the destination acknowledges
4. **Limits throughput** — only one transaction can be in-flight at a time

### Pipeline Stages

```
[AXI Write] → [Domain 1 Memory] → [Handshake In] → [Datapath] → [Handshake Out] → [Domain 1 Memory] → [AXI Read]
     |               |                    |               |                   |                      |
   PS writes     Store input         Cross to       Compute           Cross back           PS reads
   input data    data to BRAM        Domain 2       a*b + c*d       Domain 1               results
```

### Resource Usage (Estimated)

| Resource | Estimated Usage |
|----------|----------------|
| **LUTs** | ~5-10% of available |
| **FFs** | ~3-5% of available |
| **BRAM** | ~10-15% (DDR + internal BRAMs) |
| **DSP** | 4×17-bit multipliers (~2-3% of DSPs) |
| **IOs** | DDR pins + sys_clock |

## Building

### Prerequisites

- **Xilinx Vivado 2021.1** (or later, 64-bit)
- **Zynq-based board** (e.g., ZedBoard, Zybo Z7, or similar)
- DDR memory populated on target board

### Compilation Steps

1. Open **Vivado 2021.1**
2. Select **File → Open Project**
3. Open `lab5p2.xpr`
4. Select **Flow → Run Synthesis**
5. After synthesis, select **Flow → Run Implementation**
6. Generate bitstream with **Flow → Generate Bitstream**
7. Program the Zynq board and run the C software on the ARM processor

## References

- Xilinx PG085: AXI Peripheral Design Guide
- Xilinx PG058: MicroBlaze Reference Guide
- Greg Stitt, University of Florida (original author)
- IEEE 1076 VHDL Standard

> *Note: This README was generated by AI to describe the project. The source code itself was written by the user.*
