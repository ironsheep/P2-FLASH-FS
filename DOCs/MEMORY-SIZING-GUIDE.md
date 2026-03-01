# Measuring flash\_fs Memory Consumption with pnut-ts

A practical guide to determining how much hub RAM the `flash_fs` driver consumes -- method table, DAT buffers, bytecodes, and total runtime footprint -- using the pnut-ts compiler's `-m` (map) and `-l` (listing) output files.

- **Compiler**: pnut-ts v1.52.2+
- **Driver**: flash\_fs v2.0.0
- **Author**: Stephen M. Moraco, Iron Sheep Productions, LLC

---

## Table of Contents

1. [Background: flash\_fs and Hub RAM](#1-background-flash_fs-and-hub-ram)
2. [Generating Map and Listing Files](#2-generating-map-and-listing-files)
3. [Driver Standalone: Reading the Map File](#3-driver-standalone-reading-the-map-file)
4. [DAT Section Breakdown](#4-dat-section-breakdown)
5. [Impact of MAX\_FILES\_OPEN](#5-impact-of-max_files_open)
6. [Analyzing a Program That Uses flash\_fs](#6-analyzing-a-program-that-uses-flash_fs)
7. [Calculating Total Runtime Hub RAM](#7-calculating-total-runtime-hub-ram)
8. [Sizing Audit Methodology](#8-sizing-audit-methodology)
9. [Quick Reference](#9-quick-reference)

---

## 1. Background: flash\_fs and Hub RAM

The Propeller 2 has **512 KB of hub RAM**. Every Spin2 program must fit within this space along with its runtime data. The `flash_fs` driver is a single monolithic object that manages the onboard 16 MB SPI flash chip as a block-based filesystem. Because all driver state -- translation tables, per-handle buffers, and a temporary block buffer -- lives in DAT (static data), the driver has a significant and predictable memory footprint.

A compiled Spin2 program consists of three memory regions loaded into hub RAM:

| Region | Contents | When Allocated |
|---|---|---|
| **Code/Data** | Method table + DAT sections + Spin2 bytecodes, for all objects | At load time (fixed) |
| **VAR** | Instance variables declared in `VAR` blocks, for all object instances | At load time (fixed) |
| **Stack** | Call stack for each running COG (not in the binary) | At runtime |

The **binary file** (.bin) includes the code/data region plus a ~6 KB P2 loader stub. The VAR region is not stored in the binary -- it is allocated in hub RAM at load time immediately following code/data.

### Why flash\_fs is DAT-Heavy

Unlike many Spin2 objects that store per-instance state in VAR, `flash_fs` stores nearly all state in DAT. This is a deliberate design choice: DAT variables are shared across all COGs and accessible via absolute addresses, which is required for the driver's LOCK-based multi-cog synchronization. The consequence is that the driver's VAR footprint is minimal (4 bytes) while its DAT footprint dominates (~20 KB at default settings).

---

## 2. Generating Map and Listing Files

The pnut-ts compiler has two diagnostic output flags:

| Flag | Output File | Purpose |
|---|---|---|
| `-m` | `.map` | Memory map: object hierarchy, memory layout, per-object details (methods, DAT variables, sizes) |
| `-l` | `.lst` | Listing: symbol table (constants, method names, struct definitions with values) |

### Compiling the Driver Standalone

The `flash_fs` object has a `PUB null()` placeholder method as entry point 0, which allows standalone compilation:

```bash
# Driver alone -- generates map + listing + binary
pnut-ts -m -l flash_fs.spin2
```

This produces:
- `flash_fs.map` -- memory map (primary sizing tool)
- `flash_fs.lst` -- symbol listing
- `flash_fs.bin` -- binary (34,956 bytes including ~6 KB P2 loader stub)

### Compiling a Program That Uses flash\_fs

```bash
# Demo program that includes flash_fs as a child object
pnut-ts -m flash_fs_demo.spin2

# Regression test (needs include path to find flash_fs.spin2)
pnut-ts -m -I .. RegresssionTests/RT_read_write_tests.spin2
```

---

## 3. Driver Standalone: Reading the Map File

Compiling `flash_fs.spin2` standalone with `-m` produces a map file showing the driver's intrinsic footprint.

### Program Summary

```
=== PROGRAM SUMMARY ===

  Total Size:    28748 bytes (28744 code/data + 4 var bytes)
  Objects:       1
  Methods:       85
```

The driver consumes **28,748 bytes** of hub RAM total: 28,744 bytes of code/data (in the binary) plus 4 bytes of VAR (allocated at load time).

### Memory Layout

```
=== MEMORY LAYOUT ===

  Start   End      Size  Object           Instance         Overrides
  ------  ------  -----  ---------------  ---------------  ---------
  $00000  $07046  28743  flash_fs         (entry)

    CODE/DATA TOTAL:   28744 bytes

  $07048  $0704B      4  VAR SPACE        (runtime)

    PROGRAM TOTAL:     28748 bytes
```

### Object Details: Methods

The map lists all 85 methods with their entry indices:

```
    Methods:
      NULL                  Entry $00000  ($00000)
      VERSION               Entry $00001  ($00001)
      SERIAL_NUMBER         Entry $00002  ($00002)
      FORMAT                Entry $00003  ($00003)
      MOUNT                 Entry $00004  ($00004)
      ...
      FLASH_RECEIVE         Entry $00054  ($00054)
```

The first 34 methods (entries $00000–$00021) are public API. The remaining 51 (entries $00022–$00054) are private implementation methods.

### Object Details: DAT

Each DAT variable shows its type, name, relative offset within the object, and absolute hub address:

```
    DAT:
      LONG      ERRORCODE             +$00158  ($00158)
      LONG      FSLOCK                +$00178  ($00178)
      ...
      BYTE      HBLOCKBUFF            +$01FF2  ($01FF2)
      BYTE      TMPBLOCKBUFFER        +$03FF2  ($03FF2)
```

To calculate the size of a DAT variable, subtract its offset from the next variable's offset:

```
HBLOCKBUFF      at +$01FF2
TMPBLOCKBUFFER  at +$03FF2
  => HBLOCKBUFF size = $03FF2 - $01FF2 = $2000 = 8,192 bytes (2 handles x 4,096 bytes)
```

---

## 4. DAT Section Breakdown

The DAT section is the dominant consumer of the driver's memory. Using the map file offsets, here is the complete itemization:

### Region Overview

The 28,743-byte object breaks down into three regions:

| Region | Size | % of Object |
|---|---|---|
| Method table (86 entries x 4 B) | 344 B | 1.2% |
| DAT section (static data) | 20,122 B | 70.0% |
| Bytecodes (compiled methods) | 8,277 B | 28.8% |
| **Total** | **28,743 B** | **100%** |

### DAT Variables by Category

#### Driver State — Per-COG (64 bytes)

| Variable | Type | Size | Purpose |
|---|---|---|---|
| `errorCode` | LONG[8] | 32 B | Last error code, one per COG |
| `fsCogCts` | LONG[8] | 32 B | COG mount attempt counters |

#### Driver State — Global (16 bytes)

| Variable | Type | Size | Purpose |
|---|---|---|---|
| `fsLock` | LONG | 4 B | LOCK semaphore for multi-cog access |
| `fsFreeHndlCt` | LONG | 4 B | Count of available handles |
| `showRTdebug` | LONG | 4 B | Debug output flag |
| `fsMounted` | LONG | 4 B | Filesystem mounted flag |

#### Block Translation Tables (7,452 bytes)

These tables map the filesystem's 3,968 logical block IDs (range `$080`–`$FFF`) to physical flash addresses and track block states:

| Variable | Type | Size | Purpose |
|---|---|---|---|
| `IDToBlocks` | WORD[] | 5,952 B | 12-bit block address per ID |
| `IDToBlock` | LONG | 4 B | Field pointer for 12-bit access |
| `IDValids` | BYTE[] | 496 B | 1-bit valid flag per ID |
| `IDValid` | LONG | 4 B | Field pointer for 1-bit access |
| `BlockStates` | BYTE[] | 992 B | 2-bit state per ID (free/temp/head/body) |
| `BlockState` | LONG | 4 B | Field pointer for 2-bit access |

The translation tables are fixed-size -- they always cover all `BLOCKS` (= `LAST_BLOCK - FIRST_BLOCK + 1` = 3,968) regardless of how many files exist.

#### Per-Handle State (46 bytes for 2 handles)

| Variable | Type | Per Handle | Total | Purpose |
|---|---|---|---|---|
| `hStatus` | BYTE | 1 B | 2 B | Handle mode flags |
| `hHeadBlockID` | WORD | 2 B | 4 B | First block ID of file |
| `hChainBlockID` | WORD | 2 B | 4 B | First block ID of commit chain |
| `hChainBlockAddr` | WORD | 2 B | 4 B | First block address of commit chain |
| `hChainLifeCycle` | BYTE | 1 B | 2 B | Lifecycle bits for replacement |
| `hModified` | BYTE | 1 B | 2 B | Block modified flag |
| `hEndPtr` | WORD | 2 B | 4 B | Next byte pointer in block |
| `hSeekPtr` | LONG | 4 B | 8 B | Seek position within block |
| `hSeekFileOffset` | LONG | 4 B | 8 B | Seek offset within file |
| `hCircularLength` | LONG | 4 B | 8 B | Circular buffer length |

#### Per-Handle Buffers (8,448 bytes for 2 handles)

| Variable | Type | Per Handle | Total | Purpose |
|---|---|---|---|---|
| `hFilename` | BYTE[] | 128 B | 256 B | Filename buffer (127 chars + terminator) |
| `hBlockBuff` | BYTE[] | 4,096 B | 8,192 B | 4 KB data buffer for active block |

The per-handle block buffers are the largest scaling component. Each open file handle requires a full 4 KB buffer because the filesystem operates on complete flash blocks.

#### Temporary Buffer (4,096 bytes)

| Variable | Type | Size | Purpose |
|---|---|---|---|
| `tmpBlockBuffer` | BYTE[] | 4,096 B | Scratch buffer for block copy operations |

### Summary by Category

| Category | Size | % of DAT |
|---|---|---|
| Driver state (per-COG + global) | 80 B | 0.4% |
| Block translation tables | 7,452 B | 37.0% |
| Per-handle state | 46 B | 0.2% |
| Per-handle buffers (2 handles) | 8,448 B | 42.0% |
| Temporary block buffer | 4,096 B | 20.4% |
| **Total DAT** | **20,122 B** | **100%** |

The two dominant categories are **per-handle buffers** (42%) and **block translation tables** (37%). Together they account for nearly 80% of the DAT section.

---

## 5. Impact of MAX\_FILES\_OPEN

The `MAX_FILES_OPEN` constant (default: 2) controls how many files can be open simultaneously. Changing it affects per-handle state and buffers:

| MAX\_FILES\_OPEN | Handle Buffers | Handle State | DAT Delta | Total Code/Data |
|---|---|---|---|---|
| 1 | 4,224 B | 23 B | -4,247 B | ~24,497 B |
| 2 (default) | 8,448 B | 46 B | baseline | 28,744 B |
| 3 | 12,672 B | 69 B | +4,247 B | ~32,991 B |
| 4 | 16,896 B | 92 B | +8,494 B | ~37,238 B |
| 6 | 25,344 B | 138 B | +16,988 B | ~45,732 B |

**Each additional open file handle adds ~4,247 bytes** (dominated by the 4,096-byte block buffer plus 128-byte filename buffer and 23 bytes of state).

The block translation tables and temporary buffer are not affected by `MAX_FILES_OPEN` -- they remain at 7,452 B and 4,096 B respectively regardless of handle count.

---

## 6. Analyzing a Program That Uses flash\_fs

When `flash_fs` is included as a child object in a program, the map file shows each object's contribution. Here is the `flash_fs_demo` program:

### Object Hierarchy

```
=== OBJECT HIERARCHY ===

  flash_fs_demo  (6 methods)
      \-- FLASH : flash_fs  (85 methods)
```

### Memory Layout

```
=== MEMORY LAYOUT ===

  Start   End      Size  Object           Instance         Overrides
  ------  ------  -----  ---------------  ---------------  ---------
  $00000  $001E6    487  flash_fs_demo    (entry)
  $001E8  $0722E  28743  flash_fs         FLASH

    CODE/DATA TOTAL:   29232 bytes

  $07230  $07237      8  VAR SPACE        (runtime)

    PROGRAM TOTAL:     29240 bytes
```

### Per-Object Breakdown

| Object | Code/Data | % of Total | Purpose |
|---|---|---|---|
| flash\_fs\_demo (top-level) | 487 B | 1.7% | Demo application logic |
| flash\_fs (driver) | 28,743 B | 98.3% | Flash filesystem driver |
| **Total** | **29,232 B** | **100%** | |

The driver dominates at 98.3% of code/data. The demo application adds only 487 bytes of its own code. VAR is 8 bytes total (4 bytes for each object's minimum allocation).

### What the Consumer Program Adds

The consumer's overhead is small:
- **Method table**: 6 methods plus header = 7 entries x 4 bytes = 28 bytes
- **DAT**: 3 filename string constants = ~45 bytes
- **Bytecodes**: 6 compiled methods = ~414 bytes

The binary file is 35,444 bytes (29,232 code/data + ~6 KB P2 loader stub).

---

## 7. Calculating Total Runtime Hub RAM

The binary file size is NOT your runtime memory footprint. Runtime hub RAM usage is:

```
Runtime Hub RAM = Code/Data + VAR + Stacks
```

The map file gives you the first two directly from the PROGRAM SUMMARY line. Stacks must be accounted for separately.

### Stack Estimation

Every COG running Spin2 code needs a stack. The top-level COG uses the remainder of hub RAM above the program as its stack. Additional COGs launched with `cogspin()` use explicitly allocated stack buffers (typically declared in DAT or VAR).

The `flash_fs` driver itself does not launch any additional COGs -- it runs entirely within the calling COG's context using LOCK-based synchronization. So there are no hidden stack allocations within the driver.

### Complete Accounting Example

For the `flash_fs_demo` program:

```
Code/Data:           29,232 bytes   (from map: CODE/DATA TOTAL)
VAR:                      8 bytes   (from map: VAR SPACE size)
                    ---------
Program Total:       29,240 bytes

P2 Hub RAM:         524,288 bytes   (512 KB)
Available:          495,048 bytes   (for main COG stack + other uses)
```

The driver leaves ample room for application code and data. Even with `MAX_FILES_OPEN` set to 6 (~45,732 bytes for the driver alone), the total program would consume under 10% of hub RAM.

---

## 8. Sizing Audit Methodology

This section describes a repeatable process for auditing the memory footprint of `flash_fs` in your project.

### Step 1: Measure the Driver in Isolation

Compile `flash_fs.spin2` as top-level to measure its intrinsic footprint:

```bash
pnut-ts -m flash_fs.spin2
```

Record from the PROGRAM SUMMARY:
- Total code/data size (28,744 bytes at default settings)
- Method count (85)
- VAR size (4 bytes)

### Step 2: Extract Region Sizes from the Map

Open the map file and identify the three regions:

- **Method table**: from `$00000` to first DAT variable's offset (`$00158`) = 344 bytes
- **DAT section**: from first DAT variable to end of last buffer = 20,122 bytes
- **Bytecodes**: object total minus method table minus DAT = 8,277 bytes

### Step 3: Itemize the DAT Section

Walk the DAT variables in the map file. For each variable, compute its size by subtracting its offset from the next variable's offset:

```
IDTOBLOCKS      +$001A8
IDTOBLOCK       +$018E8
  => IDTOBLOCKS is $018E8 - $001A8 = $1740 = 5,952 bytes
```

Group variables into logical categories (translation tables, handle buffers, state) and total each category. See [Section 4](#4-dat-section-breakdown) for the complete breakdown.

### Step 4: Measure Your Application

Compile your top-level program with `-m` and check the map:

```bash
pnut-ts -m -I path/to/flash_fs my_application.spin2
```

Record:
- Total binary size (.bin file)
- Code/Data total (from map)
- VAR total (from map)
- Runtime hub RAM = Code/Data + VAR

### Step 5: Automate for Repeatability

For projects with many programs, create a benchmark script:

```bash
# For each source file:
pnut-ts -m [flags] "$filename"
size=$(wc -c < "$binfile")
md5=$(md5 -q "$binfile")    # or md5sum on Linux
```

This produces a repeatable baseline. When you upgrade the compiler, change `MAX_FILES_OPEN`, or refactor code, re-run the benchmark and diff against the previous run to detect size changes.

---

## 9. Quick Reference

### Generate Files

```bash
pnut-ts -m flash_fs.spin2              # Map file only
pnut-ts -l -m flash_fs.spin2           # Map + listing
pnut-ts -m -d flash_fs.spin2           # Map with debug enabled
```

### Key Map File Sections

| Section | What It Tells You |
|---|---|
| PROGRAM SUMMARY | Total size = code/data + VAR |
| OBJECT HIERARCHY | Which objects are included and their nesting |
| MEMORY LAYOUT | Per-object code/data size and address ranges |
| Object Details: Methods | Every method name and entry index |
| Object Details: DAT | Every DAT variable with offset and absolute address |

### Size Formulas

```
Binary File Size    = Code/Data + P2 Loader Stub (~6 KB)
Runtime Hub RAM     = Code/Data + VAR + Stack allocations
Object Code/Data    = Method Table + DAT Section + Bytecodes
DAT Variable Size   = (next variable offset) - (this variable offset)
Available RAM       = 524,288 - Runtime Hub RAM
```

### flash\_fs Driver Quick Reference

| Metric | Value |
|---|---|
| Code/Data (standalone) | 28,744 B |
| Methods | 85 (34 public + 51 private) |
| VAR | 4 B |
| Binary size | 34,956 B |
| DAT section | 20,122 B (70% of code/data) |
| Method table | 344 B |
| Bytecodes | 8,277 B |

### DAT Category Summary

| Category | Size | Scales With |
|---|---|---|
| Block translation tables | 7,452 B | BLOCKS (fixed at 3,968) |
| Per-handle buffers | 8,448 B | MAX\_FILES\_OPEN (default 2) |
| Temporary block buffer | 4,096 B | Fixed |
| Per-handle state | 46 B | MAX\_FILES\_OPEN (default 2) |
| Driver state | 80 B | Fixed |
| **Total DAT** | **20,122 B** | |

### Per-Handle Cost

```
Additional handle = 4,096 B (block buffer) + 128 B (filename) + 23 B (state) ≈ 4,247 B
```
