# AXI Custom Accelerator — Dual-Clock-Domain a*b + c*d Engine

Zynq-7000 project implementing a custom AXI accelerator IP that computes `a*b + c*d` on four 8-bit values with cross-domain handshake synchronization. Built for Vivado 2021.1.

## Overview

This project implements a hardware accelerator for parallel 8-bit multiplication with a dual-clock-domain architecture. The accelerator receives input data from the Zynq Processing System via AXI Lite, performs computation in a separate clock domain, and writes results back through memory using handshake-based cross-domain synchronization.

## Project Structure

| File | Description |
|------|-------------|
| `user_app.vhd` | Top-level application: AXI interface, memory mapping, datapath control |
| `memory_map.vhd` | AXI Lite memory-mapped register interface for configuration |
| `datapath.vhd` | Core computation: splits 32-bit word into four 8-bit values, computes two multiplications |
| `handshake.vhd` | Cross-clock-domain handshake synchronizer |
| `addr_gen_in.vhd` | Input address generator |
| `addr_gen_out.vhd` | Output address generator |
| `ram.vhd` | Synchronous memory for input/output buffering |
| `config_pkg.vhd` / `user_pkg.vhd` | Configuration constants and type definitions |
| `delay.vhd` / `reg.vhd` | Utility components |

## Hardware

- **Device:** Xilinx Zynq-7000 XC7Z020 (xc7z020clg484-1)
- **Tool:** Vivado 2021.1
- **Language:** VHDL-2008

## Architecture

**Dual-clock-domain design:**

- **Clock Domain 1 (100 MHz):** Zynq PS clock. Handles AXI communication, input/output memory, and address generation.
- **Clock Domain 2 (user):** Accelerator computation domain. Processes 8-bit values in the datapath.

Data flows from PS through AXI into Domain 1, crosses to Domain 2 via handshake synchronizers, computes `a*b + c*d` (17-bit result), crosses back, and writes to output memory.

## Building

1. Open `lab5p2.xpr` in Vivado
2. Run Synthesis and Implementation
3. Generate bitstream and export to SDK for PS-side software
