# Measuring flash\_fs Memory Consumption with pnut-ts

A practical guide to determining how much hub RAM the `flash_fs` driver consumes - the method table, the DAT buffers, the bytecodes and the total runtime footprint - using the pnut-ts compiler's `-m` (map) and `-l` (listing) output files.

- **Compiler**: pnut-ts v1.55.12 (every figure below was measured with it)
- **Driver**: flash\_fs v2.1.0
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

The Propeller 2 has **512 KB of hub RAM**. Every Spin2 program must fit within this space along with its runtime data. The `flash_fs` driver is a single monolithic object that manages the onboard 16 MB SPI flash chip as a block-based filesystem. Because all driver state - translation tables, per-handle buffers and a temporary block buffer - lives in DAT (static data), the driver has a significant and predictable memory footprint.

A compiled Spin2 program consists of three memory regions loaded into hub RAM:

| Region | Contents | When Allocated |
|---|---|---|
| **Code/Data** | Method table + DAT sections + Spin2 bytecodes, for all objects | At load time (fixed) |
| **VAR** | Instance variables declared in `VAR` blocks, for all object instances | At load time (fixed) |
| **Stack** | Call stack for each running COG (not in the binary) | At runtime |

The **binary file** (.bin) includes the code/data region plus a ~6 KB P2 loader stub. The VAR region is not stored in the binary - it is allocated in hub RAM at load time immediately following code/data.

### Why flash\_fs is DAT-Heavy

Unlike many Spin2 objects that store per-instance state in VAR, `flash_fs` stores nearly all state in DAT. This is a deliberate design choice: DAT variables are shared across all COGs and accessible via absolute addresses, which is required for the driver's LOCK-based multi-cog synchronization. The consequence is that the driver's VAR footprint is minimal (8 bytes) while its DAT footprint dominates (about 20 KB at default settings).

---

## 2. Generating Map and Listing Files

The pnut-ts compiler has two diagnostic output flags:

| Flag | Output File | Purpose |
|---|---|---|
| `-m` | `.map` | Memory map: object tree, memory layout, per-object details (methods, DAT variables, VAR) |
| `-l` | `.lst` | Listing: symbol table (constants, method names, struct definitions with values) |

### Compiling the Driver Standalone

The `flash_fs` object has a `PUB null()` placeholder method as entry point 0, which allows standalone compilation:

```bash
# Driver alone -- generates map + listing + binary
pnut-ts -m -l flash_fs.spin2
```

This produces:
- `flash_fs.map` - memory map (primary sizing tool)
- `flash_fs.lst` - symbol listing
- `flash_fs.bin` - binary (38,684 bytes including the ~6 KB P2 loader stub)

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

### Summary

```
=== SUMMARY ===

  The top object became 1 instance, built from 1 image; no image is shared.

  Code/DAT bytes  32404
  VAR bytes           8
  Total bytes     32412
  Hub base        $01888
```

The driver consumes **32,412 bytes** of hub RAM in total: 32,404 bytes of code/data (in the binary) plus 8 bytes of VAR (allocated at load time).

### Memory Layout

```
=== MEMORY LAYOUT ===

  Images
  Range           Size  Image  Source          Instances
  -------------  -----  -----  --------------  ---------
  $00000-$07E92  32403  #1     flash_fs.spin2  (top)

  VAR blocks
  Range          Size  Image  Instance
  -------------  ----  -----  --------
  $07E94-$07E9B     8  #1     (top)
```

### Object Details: Methods

The map lists all 101 methods with their offsets:

```
  Methods
  Name                          Offset   Address
  ----------------------------  -------  -------
  NULL                          +$0506C  $0506C
  VERSION                       +$0506E  $0506E
  SERIAL_NUMBER                 +$0507D  $0507D
  FORMAT                        +$050D7  $050D7
  MOUNT                         +$05166  $05166
  ...
  FLASH_RECEIVE                 +$07E4F  $07E4F
```

The first 34 methods (`NULL` to `STRING_FOR_ERROR`) are the public API. The remaining 67 are private implementation methods.

### Object Details: DAT

Each DAT variable shows its type, name and offset within the object:

```
  DAT
  Type  Name                Offset   Address
  ----  ------------------  -------  -------
  LONG  ERRORCODE           +$00198  $00198
  LONG  FSLOCK              +$001B8  $001B8
  ...
  BYTE  HBLOCKBUFF          +$02064  $02064
  BYTE  TMPBLOCKBUFFER      +$04064  $04064
```

To calculate the size of a DAT variable, subtract its offset from the next variable's offset:

```
HBLOCKBUFF      at +$02064
TMPBLOCKBUFFER  at +$04064
  => HBLOCKBUFF size = $04064 - $02064 = $2000 = 8,192 bytes (2 handles x 4,096 bytes)
```

---

## 4. DAT Section Breakdown

The DAT section is the dominant consumer of the driver's memory. Using the map file offsets, here is the complete itemization:

### Region Overview

The 32,403-byte image breaks down into three regions:

| Region | Size | % of Image |
|---|---|---|
| Method table (102 entries x 4 B) | 408 B | 1.3% |
| DAT section (static data) | 20,180 B | 62.3% |
| Bytecodes (compiled methods) | 11,815 B | 36.5% |
| **Total** | **32,403 B** | **100%** |

### DAT Variables by Category

#### Driver State - Per-COG (64 bytes)

| Variable | Type | Size | Purpose |
|---|---|---|---|
| `errorCode` | LONG[8] | 32 B | Last error code, one per COG |
| `fsCogCts` | LONG[8] | 32 B | Lock-election counts, one per COG |

#### Driver State - Global (40 bytes)

| Variable | Type | Size | Purpose |
|---|---|---|---|
| `fsLock` | LONG | 4 B | LOCK semaphore for multi-cog access |
| `fsElection` | LONG | 4 B | State of the election that creates the lock |
| `fsFreeHndlCt` | LONG | 4 B | Count of available handles |
| `showRTdebug` | LONG | 4 B | Debug output flag |
| `fsMounted` | LONG | 4 B | Filesystem mounted flag |
| `fsDeviceFault` | LONG | 4 B | Set after a flash timeout, cleared by `mount()` |
| `fsFlashWaitMs` | LONG | 4 B | Longest flash wait, in milliseconds |
| `fsFaultCountdown` | LONG | 4 B | Flash fault countdown (off in normal operation) |
| `fsSkipCreateChecks` | LONG | 4 B | Test flag, off in normal operation |
| `fsTargetBlock` | LONG | 4 B | Test flag, off in normal operation |

#### Block Translation Tables (7,452 bytes)

These tables map the filesystem's 3,968 logical block IDs (the 4 KB blocks at flash addresses `$080` to `$FFF`) to physical flash addresses and track block states:

| Variable | Type | Size | Purpose |
|---|---|---|---|
| `IDToBlocks` | WORD[] | 5,952 B | 12-bit block address per ID |
| `IDToBlock` | LONG | 4 B | Field pointer for 12-bit access |
| `IDValids` | BYTE[] | 496 B | 1-bit valid flag per ID |
| `IDValid` | LONG | 4 B | Field pointer for 1-bit access |
| `BlockStates` | BYTE[] | 992 B | 2-bit state per block (free/temp/head/body) |
| `BlockState` | LONG | 4 B | Field pointer for 2-bit access |

The translation tables are fixed-size - they always cover all `BLOCKS` (= `LAST_BLOCK - FIRST_BLOCK + 1` = 3,968) regardless of how many files exist.

#### Per-Handle State (80 bytes for 2 handles, 40 bytes each)

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
| `hHeadPending` | BYTE | 1 B | 2 B | A `"w+"` head block not yet committed |
| `hTrimPending` | BYTE | 1 B | 2 B | A circular trim still owed after a flush |
| `hWindowStart` | LONG | 4 B | 8 B | First byte of an old-format circular read |
| `hReplacedID` | LONG | 4 B | 8 B | Head block of the file this handle replaces at close |
| `hCacheBlockID` | WORD | 2 B | 4 B | Seek cache: block last located |
| `hCacheStart` | LONG | 4 B | 8 B | Seek cache: file offset of that block |
| `hCacheOldFmt` | BYTE | 1 B | 2 B | Seek cache: old-format head flag |

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
| Driver state (per-COG + global) | 104 B | 0.5% |
| Block translation tables | 7,452 B | 36.9% |
| Per-handle state (2 handles) | 80 B | 0.4% |
| Per-handle buffers (2 handles) | 8,448 B | 41.9% |
| Temporary block buffer | 4,096 B | 20.3% |
| **Total DAT** | **20,180 B** | **100%** |

The two dominant categories are **per-handle buffers** (42%) and **block translation tables** (37%). Together they account for nearly 80% of the DAT section.

---

## 5. Impact of MAX\_FILES\_OPEN

The `MAX_FILES_OPEN` constant (default: 2) controls how many files can be open simultaneously. Changing it affects per-handle state and buffers.

**Each handle takes 4,264 bytes of hub RAM**: the 4,096-byte block buffer, the 128-byte filename buffer and 40 bytes of state. The figure is the growth of the image between a build with `MAX_FILES_OPEN = 2` and one with 3 (pnut-ts v1.55.12 listing, `-l`), and the code/data in the map grows by the same amount from 2 to 4 (a build with `MAX_FILES_OPEN = 4` is 47,212 bytes as a binary, 8,528 bytes more than the default build).

| MAX\_FILES\_OPEN | Handle Buffers | Handle State | DAT Delta | Total Code/Data |
|---|---|---|---|---|
| 1 | 4,224 B | 40 B | -4,264 B | 28,140 B (computed) |
| 2 (default) | 8,448 B | 80 B | baseline | 32,404 B |
| 3 | 12,672 B | 120 B | +4,264 B | 36,668 B (computed) |
| 4 | 16,896 B | 160 B | +8,528 B | 40,932 B |
| 6 | 25,344 B | 240 B | +17,056 B | 49,460 B (computed) |

Rows marked *computed* multiply the per-handle figure; the other rows come from a compiled map.

The block translation tables and temporary buffer are not affected by `MAX_FILES_OPEN` - they remain at 7,452 B and 4,096 B respectively regardless of handle count.

---

## 6. Analyzing a Program That Uses flash\_fs

When `flash_fs` is included as a child object in a program, the map file shows each object's contribution. Here is the `flash_fs_demo` program:

### Object Tree

```
=== OBJECT TREE ===

  Instance  Image  Source               Overrides
  --------  -----  -------------------  ---------
  (top)     #1     flash_fs_demo.spin2  -
    FLASH   #2     flash_fs.spin2       -
```

### Memory Layout

```
=== MEMORY LAYOUT ===

  Images
  Range           Size  Image  Source               Instances
  -------------  -----  -----  -------------------  ---------
  $00000-$001EA    491  #1     flash_fs_demo.spin2  (top)
  $001EC-$0807E  32403  #2     flash_fs.spin2       FLASH

  VAR blocks
  Range          Size  Image  Instance
  -------------  ----  -----  --------
  $08080-$08083     4  #1     (top)
  $08084-$0808B     8  #2     FLASH
```

### Per-Object Breakdown

| Object | Code/Data | % of Total | Purpose |
|---|---|---|---|
| flash\_fs\_demo (top-level) | 491 B | 1.5% | Demo application logic |
| flash\_fs (driver) | 32,403 B | 98.5% | Flash filesystem driver |
| **Total** | **32,896 B** | **100%** | (includes 2 bytes of alignment padding) |

The driver dominates at 98.5% of code/data. The demo application adds only 491 bytes of its own code. VAR is 12 bytes in total (4 bytes for the demo and 8 for the driver).

The binary file is 39,176 bytes (32,896 code/data plus the ~6 KB P2 loader stub).

---

## 7. Calculating Total Runtime Hub RAM

The binary file size is NOT your runtime memory footprint. Runtime hub RAM usage is:

```
Runtime Hub RAM = Code/Data + VAR + Stacks
```

The map file gives you the first two directly from the SUMMARY block. Stacks must be accounted for separately.

### Stack Estimation

Every COG running Spin2 code needs a stack. The top-level COG uses the remainder of hub RAM above the program as its stack. Additional COGs launched with `cogspin()` use explicitly allocated stack buffers (typically declared in DAT or VAR).

The `flash_fs` driver itself does not launch any additional COGs - it runs entirely within the calling COG's context using LOCK-based synchronization. So there are no hidden stack allocations within the driver.

### Complete Accounting Example

For the `flash_fs_demo` program:

```
Code/Data:           32,896 bytes   (from map: Code/DAT bytes)
VAR:                     12 bytes   (from map: VAR bytes)
                    ---------
Program Total:       32,908 bytes

P2 Hub RAM:         524,288 bytes   (512 KB)
Available:          491,380 bytes   (for main COG stack + other uses)
```

The driver leaves ample room for application code and data. Even with `MAX_FILES_OPEN` set to 6 (about 49,460 bytes for the driver alone), the total program would consume under 10% of hub RAM.

---

## 8. Sizing Audit Methodology

This section describes a repeatable process for auditing the memory footprint of `flash_fs` in your project.

### Step 1: Measure the Driver in Isolation

Compile `flash_fs.spin2` as top-level to measure its intrinsic footprint:

```bash
pnut-ts -m flash_fs.spin2
```

Record from the SUMMARY:
- Total code/data size (32,404 bytes at default settings)
- Method count (101)
- VAR size (8 bytes)

### Step 2: Extract Region Sizes from the Map

Open the map file and identify the three regions:

- **Method table**: from `$00000` to the first DAT variable's offset (`$00198`) = 408 bytes
- **DAT section**: from the first DAT variable (`ERRORCODE`) to the first method (`NULL`, `$0506C`) = 20,180 bytes
- **Bytecodes**: image size minus method table minus DAT = 11,815 bytes

### Step 3: Itemize the DAT Section

Walk the DAT variables in the map file. For each variable, compute its size by subtracting its offset from the next variable's offset:

```
IDTOBLOCKS      +$001F8
IDTOBLOCK       +$01938
  => IDTOBLOCKS is $01938 - $001F8 = $1740 = 5,952 bytes
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
| SUMMARY | Total size = code/data + VAR |
| OBJECT TREE | Which objects are included and their nesting |
| MEMORY LAYOUT | Per-image code/data size and address ranges, and the VAR blocks |
| Object Details: Methods | Every method name and offset |
| Object Details: DAT | Every DAT variable with offset and address |

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
| Code/Data (standalone) | 32,404 B |
| Methods | 101 (34 public + 67 private) |
| VAR | 8 B |
| Binary size | 38,684 B |
| DAT section | 20,180 B (62% of the image) |
| Method table | 408 B |
| Bytecodes | 11,815 B |

### DAT Category Summary

| Category | Size | Scales With |
|---|---|---|
| Block translation tables | 7,452 B | BLOCKS (fixed at 3,968) |
| Per-handle buffers | 8,448 B | MAX\_FILES\_OPEN (default 2) |
| Temporary block buffer | 4,096 B | Fixed |
| Per-handle state | 80 B | MAX\_FILES\_OPEN (default 2) |
| Driver state | 104 B | Fixed |
| **Total DAT** | **20,180 B** | |

### Per-Handle Cost

```
Additional handle = 4,096 B (block buffer) + 128 B (filename) + 40 B (state) = 4,264 B
```
