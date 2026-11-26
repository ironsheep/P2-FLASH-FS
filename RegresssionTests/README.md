# P2-FLASH-FS / Regresssion Tests

![Project Maintenance][maintenance-shield]

[![License][license-shield]](LICENSE)

These are regression test files that I'm using to certify the FS operation with each release.  All tests must pass! The regression test programs are versioned here so you can repeat this testing any time to verify your driver operation.

The point of these tests is to exercise each method attempting to check both normal and error/exception cases. Each expectation is what the documented contract says, not what the driver happens to do.

## Table of Contents

On this Page:

- [Test Coverage](#test-coverage) - which programs exercise which method and mode
- [Behaviours the programs check](#behaviours-the-programs-check) - the rules, and the program that holds each
- [Running the tests](#running-the-tests) - building and running with `tools/run_tests.sh`
- [The Test files](#the-test-files) - every program, and its result
- [Test history](#test-history)

## Test Coverage

This table says which test programs call each public method, and for the open modes, which programs open a file in the mode. A program is listed only where its source calls the method or opens the mode. `RT_utilities.spin2` holds the helpers the programs share, among them the typed write and read helpers (`wr_word()`, `wr_long()`, `wr_str()`, `rd_word()`, `rd_long()`) that `RT_read_write_tests` and `RT_write_append_tests` run.

| Public Method | Mode or case | Programs | Notes
| --- | --- | --- | --- |
| PUB version() : result | | `RT_error_paths_tests`, `RT_full_flash_tests` | the harness also prints it in every banner
| PUB serial\_number() : sn\_hi, sn\_lo | mounted, and not mounted | `RT_read_write_tests`, `RT_write_append_tests`, `RT_mount_handle_basics_tests`, `RT_error_paths_tests` |
| PUB mount() : status | clean flash | every program | |
| PUB mount() : status | a bad block, a duplicate ID, a head never activated, out-of-range fields | `RT_power_loss_tests` | status and survivors checked after the repair
| PUB mount() : status | no free hub lock, from two cogs, after an unmount from another cog | `RT_mount_state_tests` | |
| PUB mount() : status | `MAX_FILES_OPEN` below 1, `HANDLE_BASE` of 2 | `RT_single_handle_smoke_tests`, `RT_error_paths_tests` | |
| PUB can\_mount() : bool | clean flash, bad block, mounted | `RT_mount_state_tests`, `RT_power_loss_tests`, `RT_error_paths_tests` | also called by `RT_full_flash_tests`, `RT_single_handle_smoke_tests`, `RT_performance_baseline`, `RT_read_circular_compat_tests`, `RT_read_write_circular_tests`
| PUB mounted() : bool, PUB null() | | `RT_mount_state_tests`, `RT_error_paths_tests` | neither changes `error()`
| PUB unmount() : status | no writer, and a writer of each kind open | `RT_read_write_tests`, `RT_mount_handle_basics_tests`, `RT_mount_state_tests`, `RT_error_paths_tests`, `RT_rmw_extended_tests`, `RT_full_flash_tests`, `RT_power_loss_tests` | `RT_mount_state_tests` holds the writer cases
| PUB format() : status | | every program that starts from a clean flash | `RT_mount_state_tests` formats while another cog loops on `open()`
| PUB error() : result | | every program | `RT_error_paths_tests` holds the per-call contract
| PUB open(p\_filename,"r") : handle | new file (refused), existing file | `RT_read_write_tests`, `RT_read_seek_tests`, `RT_rmw_extended_tests`, `RT_error_paths_tests` and every program that reads a file back |
| PUB open(p\_filename,"w") : handle | new file, existing file, closed with and without a write | `RT_rmw_extended_tests`, `RT_read_write_tests`, `RT_boundary_size_tests`, `RT_filename_tests` | the delete-on-empty-close rule is in `RT_rmw_extended_tests`
| PUB open(p\_filename,"a") : handle | new file, existing file, closed with and without a write | `RT_write_append_tests`, `RT_rmw_extended_tests` |
| PUB open(p\_filename,"r+") : handle | new file (refused), existing file, read, write inside and at the end, grow | `RT_read_modify_write_tests`, `RT_rmw_extended_tests`, `RT_seek_edge_tests`, `RT_boundary_size_tests`, `RT_full_flash_tests`, `RT_mount_state_tests`, `RT_error_paths_tests`, `RT_power_loss_tests` |
| PUB open(p\_filename,"w+") : handle | new file, existing file, closed with and without a write, flush | `RT_rmw_extended_tests`, `RT_seek_edge_tests`, `RT_full_flash_tests`, `RT_mount_state_tests`, `RT_error_paths_tests`, `RT_power_loss_tests` |
| PUB open(p\_filename, other mode) : handle | `"a+"` and other letters (E\_FILE\_MODE) | `RT_error_paths_tests`, `RT_rmw_extended_tests` |
| PUB open\_circular(p\_filename,"r") : handle | new-format and old-format (v1.4) files | `RT_read_write_circular_tests`, `RT_read_circular_compat_tests`, `RT_seek_edge_tests`, `RT_error_paths_tests` |
| PUB open\_circular(p\_filename,"a") : handle | create, append, trim at close | `RT_read_write_circular_tests`, `RT_seek_edge_tests`, `RT_full_flash_tests`, `RT_mount_state_tests`, `RT_error_paths_tests` | a trim that finds no free block, then a later close, is in `RT_full_flash_tests`
| PUB flush(handle) : status | "a", "w", "w+", "r+", circular | `RT_write_append_tests`, `RT_rmw_extended_tests`, `RT_full_flash_tests`, `RT_power_loss_tests`, `RT_error_paths_tests`, `RT_mount_handle_basics_tests` | a flush that finds no free block, then a later close that commits, is in `RT_full_flash_tests`
| PUB close(handle) : status | every mode, a handle closed twice, a handle never opened | every program that opens a file | the double close is in `RT_error_paths_tests`
| PUB rename(p\_old\_filename, p\_new\_filename) : status | mounted, not mounted, new name taken, old name missing, open file, full flash | `RT_rename_delete_tests`, `RT_full_flash_tests`, `RT_error_paths_tests`, `RT_filename_tests`, `RT_mount_handle_basics_tests` | the order of the checks is in `RT_rename_delete_tests`
| PUB delete(p\_filename) : status | mounted, not mounted, file open, file missing | `RT_rename_delete_tests`, `RT_error_paths_tests`, `RT_filename_tests`, `RT_mount_handle_basics_tests` |
| PUB create\_file(p\_filename, fill\_value, byte\_count) : status | lengths at the block edges, length 0 or less, full flash, name in use | `RT_boundary_size_tests`, `RT_read_write_tests`, `RT_full_flash_tests`, `RT_error_paths_tests`, `RT_power_loss_tests`, `RT_filename_tests`, `RT_mount_handle_basics_tests` |
| PUB exists(p\_filename) : result | present, absent, bad name | `RT_rename_delete_tests`, `RT_filename_tests`, `RT_rmw_extended_tests`, `RT_write_append_tests`, `RT_error_paths_tests`, `RT_power_loss_tests`, `RT_mount_handle_basics_tests` |
| PUB file\_size(p\_filename) : size\_in\_bytes | plain and trimmed circular files | `RT_read_write_tests`, `RT_boundary_size_tests`, `RT_seek_edge_tests`, `RT_read_write_circular_tests`, `RT_rmw_extended_tests`, `RT_write_append_tests`, `RT_rename_delete_tests`, `RT_filename_tests`, `RT_error_paths_tests`, `RT_power_loss_tests` |
| PUB file\_size\_for\_handle(handle) : size\_in\_bytes | read, old-format circular, handle not open | `RT_read_seek_tests`, `RT_read_circular_compat_tests`, `RT_seek_edge_tests`, `RT_error_paths_tests` |
| PUB file\_size\_unused(p\_filename) : size\_in\_bytes\_unused | | `RT_read_write_block_tests`, `RT_boundary_size_tests`, `RT_read_modify_write_tests`, `RT_read_write_8cog_tests`, `RT_seek_edge_tests`, `RT_filename_tests`, `RT_error_paths_tests`, `RT_mount_state_tests`, `RT_mount_handle_basics_tests` |
| PUB seek(handle, position, whence) : result | "r", "r+", "w+", circular; SK\_FILE\_START and SK\_CURRENT\_POSN; POSX; before the first byte; past the end | `RT_read_seek_tests`, `RT_seek_edge_tests`, `RT_read_modify_write_tests`, `RT_rmw_extended_tests`, `RT_read_circular_compat_tests` | every handle method on a handle in a mode that does not serve it (E\_FILE\_MODE), a seek among them, is in `RT_error_paths_tests`
| PUB write(handle, p\_buffer, count) : result | "w", "a", "r+", "w+"; across block edges; a negative count | `RT_read_write_block_tests`, `RT_boundary_size_tests`, `RT_rmw_extended_tests`, `RT_full_flash_tests`, `RT_error_paths_tests` |
| PUB wr\_byte(handle, byte\_value) : result | "w", "a" | `RT_write_append_tests`, `RT_full_flash_tests`, `RT_error_paths_tests`, and the helpers in `RT_utilities` |
| PUB wr\_word(), wr\_long(), wr\_str() : result | "w", "a"; a short write on a full flash | `RT_read_write_tests`, `RT_write_append_tests` (typed helpers in `RT_utilities`), `RT_read_write_8cog_tests`, `RT_full_flash_tests`, `RT_error_paths_tests`, `RT_mount_handle_basics_tests` |
| PUB read(handle, p\_buffer, count) : bytes\_read | "r", "r+", "w+"; across block edges; at the end; a negative count | `RT_read_write_block_tests`, `RT_read_write_tests`, `RT_boundary_size_tests`, `RT_seek_edge_tests`, `RT_rmw_extended_tests`, `RT_error_paths_tests` |
| PUB rd\_byte(handle) : value | "r", "r+" | `RT_read_write_tests`, `RT_rmw_extended_tests`, `RT_error_paths_tests` |
| PUB rd\_word(), rd\_long() : value | "r", "r+"; fewer bytes left than asked | `RT_read_write_tests` (typed helpers in `RT_utilities`), `RT_read_write_8cog_tests`, `RT_rmw_extended_tests`, `RT_error_paths_tests`, `RT_mount_handle_basics_tests` |
| PUB rd\_str(handle, p\_str, buf\_size) : result | buffer edges; truncated and incomplete strings; "r+" | `RT_rd_str_boundary_tests`, `RT_read_write_tests`, `RT_rmw_extended_tests`, `RT_error_paths_tests` |
| PUB directory(p\_block\_id, p\_filename, p\_file\_size) | end of list; a 127-character name | `RT_filename_tests`, `RT_mount_handle_basics_tests`, `RT_seek_edge_tests`, `RT_mount_state_tests`, `RT_error_paths_tests` |
| PUB stats() : used\_blocks, free\_blocks, file\_count | | `RT_rename_delete_tests`, `RT_mount_handle_basics_tests`, `RT_boundary_size_tests`, `RT_filename_tests`, `RT_full_flash_tests`, `RT_error_paths_tests`, `RT_mount_state_tests`, `RT_power_loss_tests` |
| PUB string\_for\_error(error\_code) : p\_interpretation | every code, an unknown code | `RT_error_paths_tests` | the harness uses it for every failure line

The coverage is the call sites in the programs. The test counts in [The Test files](#the-test-files) say how many checks each program makes.

## Behaviours the programs check

| Behaviour | Program |
| --- | --- |
| Every open mode on a new and on an existing file: what happens at open, at write, and at close with and without a write; `"w"` and `"w+"` on an existing file closed with no write delete it and return SUCCESS | `RT_rmw_extended_tests` |
| `error()` holds SUCCESS or the call's own code after every call; the four accessors leave a pending code alone | `RT_error_paths_tests` |
| A handle out of range, not open, closed, or closed twice gives E\_BAD\_HANDLE and disturbs no other handle | `RT_error_paths_tests` |
| E\_DRIVE\_FULL from every route: `open()`, `write()` (and from another cog), `open_circular()`, `create_file()`, `rename()`, a close that finds no block, a flush that finds no block, an unmount whose first close fails | `RT_full_flash_tests` |
| A write past the end through "r+" and "w+" grows the file; a seek past the end is refused | `RT_rmw_extended_tests`, `RT_seek_edge_tests` |
| File sizes at the edges of the block layout (head block, head plus one body, 64 KB, 1 MB) | `RT_boundary_size_tests` |
| Names of 1 and 127 characters work; empty, NULL and 128-character names are refused by every call that takes a name | `RT_filename_tests` |
| Block states a power cut can leave, and the flash timeout injected at each step of a commit | `RT_power_loss_tests` |
| Mount state, the lock, and the handle pool across the open modes; `mount()` and `unmount()` from several cogs | `RT_mount_state_tests`, `RT_read_write_8cog_tests` |
| `rd_str()` with a buffer one and two bytes short of the string, exactly as long, 1 or 2 bytes, and a string cut off by the end of the file | `RT_rd_str_boundary_tests` |
| A driver built with `MAX_FILES_OPEN` of 1 works; one built with 0 refuses to mount | `RT_single_handle_smoke_tests` |
| A circular file written by v1.4 reads through its window | `RT_read_circular_compat_tests` |
| Timing of reads, writes, opens, seeks, mount, `can_mount()` and `format()`, in system clock ticks and µs | `RT_performance_baseline` |

## Running the tests

The programs call the driver's `TEST_` methods, which sit below the `REMOVE BEFORE FLIGHT` line at the end of `flash_fs.spin2`. The shipped driver has that block commented out, and the runner never edits it: **tools/run_tests.sh** writes a hook-enabled copy of the driver to `RegresssionTests/build/flash_fs.spin2` (the one line containing `REMOVE BEFORE FLIGHT` gets its leading `{` changed to `'{`), compiles each program against that copy with **pnut-ts**, and on the macOS host downloads and runs each one with **pnut-term-ts**, then judges its log. The repository's own `flash_fs.spin2` is only ever read.

```bash
# compile every program, do not run anything (the default off the macOS host)
tools/run_tests.sh --compile-only

# compile, download, run and judge every program (the default on the macOS host)
tools/run_tests.sh --run

# one program only
tools/run_tests.sh --run RT_rmw_extended_tests

# run the suite with a driver built another way (replaces the default value of a CON constant)
tools/run_tests.sh --run --set HANDLE_BASE=1
tools/run_tests.sh --run --set MAX_FILES_OPEN=1 RT_single_handle_smoke_tests

# judge a log you already have, compiling and running nothing
tools/run_tests.sh --judge RegresssionTests/RT_rmw_extended_tests.log
```

| Option | What it does |
| --- | --- |
| `--compile-only` / `--run` | compile only, or compile, download, run and capture |
| `--set NAME=VALUE` | replace the default value of the CON constant NAME in the generated driver copy |
| `--define SYMBOL` | define a preprocessor symbol for every program (for example `FULL_FLASH_GUARD_ONLY`) |
| `--timeout SECONDS` | per-program run timeout (default 600) |
| `--driver FILE` | test this driver file instead of the repository's `flash_fs.spin2` |
| `--judge LOGFILE` | judge an existing log and compile nothing |

The runner prints one line per program: `PASS`, `FAIL`, `UNKNOWN` (no usable summary in the log) or, in compile-only mode, `COMPILED`; and a `TOTAL` line. It exits 0 when every program passed or compiled. A program passes when its log carries a `RESULT: PASS` line with equal counts. A plain run writes the log to `RegresssionTests/<program>.log`, replacing the tracked log; a run with `--set` or `--define` writes under `RegresssionTests/build/` so a tracked log is only replaced by a plain run. `tools/run_tests.sh --help` lists everything.

Running a program needs the bench: a P2 Edge on the host's serial port. `--compile-only` needs none and checks only that every program compiles against the driver.

#### Determine debug output routing (RT_*.spin2 files)

At the head of each of test RT .spin2 files you want to run look for the debug output lines:

```spin2
{
    ' debug via serial to RPi (using RPi gateway pins)
    DEBUG_PIN_TX = 57           ' GRY GPIO 10
    DEBUG_PIN_RX = 56           ' WHT GPIO 8 (gnd is BLK GPIO 6)
    DEBUG_WINDOWS_OFF = -1      ' no debug windows showing
    DEBUG_BAUD = 2_000_000      ' comms at 2Mbit
'}
```

These lines when uncommented route the debug serial to PINs 56/57 which I connect to the a Raspberry Pi for logging as there is lot of output from the test runs.

In their present form (commented out) the debug output just goes to the debug window where you are running the compiler.

## The Test files

Each program prints a `RESULT:` line with its pass and fail counts when it ends, and the runner reads that line. The counts come from the final run of the release: v2.1.0 on a P2 Edge at a 320 MHz system clock, built with pnut-ts v1.55.12, 2026-11-25. Every program passed: 2,107 tests in 20 programs, plus the 19 checks of the timing program. The log beside each program is the log of that run.

| File | Purpose | Result |
| --- | --- | --- |
| [RT\_utilities.spin2](RT_utilities.spin2) | Utility methods common to all test files: the banner with the driver version, the random seed, the typed write and read helpers, the pass and fail counts and the `RESULT:` line | - |
| [RT\_mount\_handle\_basics\_tests.spin2](RT_mount_handle_basics_tests.spin2) | Every method when the filesystem is not mounted, when out of handles, and with an illegal handle | PASS 57/57 - [log](RT_mount_handle_basics_tests.log) |
| [RT\_read\_write\_tests.spin2](RT_read_write_tests.spin2) | The read/write basic types: `wr_byte()`, `wr_word()`, `wr_long()`, `wr_str()` and their readers, `directory()`, `create_file()`, `unmount()` and `mount()` | PASS 142/142 - [log](RT_read_write_tests.log) |
| [RT\_read\_write\_block\_tests.spin2](RT_read_write_block_tests.spin2) | `read()`, `write()` and `file_size_unused()` in one block, spanning two blocks, spanning three | PASS 40/40 - [log](RT_read_write_block_tests.log) |
| [RT\_read\_seek\_tests.spin2](RT_read_seek_tests.spin2) | The open for read seek test suite, with `SK_CURRENT_POSN` | PASS 88/88 - [log](RT_read_seek_tests.log) |
| [RT\_write\_append\_tests.spin2](RT_write_append_tests.spin2) | The open for append test suite, with `flush()` | PASS 129/129 - [log](RT_write_append_tests.log) |
| [RT\_read\_write\_circular\_tests.spin2](RT_read_write_circular_tests.spin2) | `open_circular()` for read and append: blocks are added and removed as they should be, and a read starts at the byte it should | PASS 279/279 - [log](RT_read_write_circular_tests.log) |
| [RT\_read\_write\_8cog\_tests.spin2](RT_read_write_8cog_tests.spin2) | The multi-cog test suite | PASS 270/270; the total varies from run to run, with the random lengths the cogs draw - [log](RT_read_write_8cog_tests.log), [sorted by cog](RT_read_write_8cog_tests_byCog.log) |
| [RT\_read\_modify\_write\_tests.spin2](RT_read_modify_write_tests.spin2) | Read/modify/write with "r+" and "w+" | PASS 103/103 - [log](RT_read_modify_write_tests.log) |
| [RT\_read\_circular\_compat\_tests.spin2](RT_read_circular_compat_tests.spin2) | Reading circular files written by v1.4 (an old-format head block) through `open_circular()`, with `seek()` and `file_size_for_handle()` | PASS 94/94 - [log](RT_read_circular_compat_tests.log) |
| [RT\_rmw\_extended\_tests.spin2](RT_rmw_extended_tests.spin2) | Every open mode on a new and on an existing file; "r+" and "w+" reads, seeks, flushes, remounts and writes at and past the end; delete on empty close | PASS 132/132 - [log](RT_rmw_extended_tests.log) |
| [RT\_seek\_edge\_tests.spin2](RT_seek_edge_tests.spin2) | The edges of `seek()`: before the first byte, the end of a file and of an empty file, relative seeks, bad `whence`, append handles, circular limits, seeks after an edit, a trimmed circular file | PASS 87/87 - [log](RT_seek_edge_tests.log) |
| [RT\_boundary\_size\_tests.spin2](RT_boundary_size_tests.spin2) | File sizes at the block edges, 64 KB and 1 MB files by CRC, reads and writes across block boundaries from every offset | PASS 28/28 - [log](RT_boundary_size_tests.log) |
| [RT\_rd\_str\_boundary\_tests.spin2](RT_rd_str_boundary_tests.spin2) | The buffer size edges of `rd_str()` | PASS 39/39 - [log](RT_rd_str_boundary_tests.log) |
| [RT\_filename\_tests.spin2](RT_filename_tests.spin2) | The names the driver accepts and refuses, and `directory()` with a 127-character name | PASS 53/53 - [log](RT_filename_tests.log) |
| [RT\_rename\_delete\_tests.spin2](RT_rename_delete_tests.spin2) | `rename()` and `delete()` on a mounted filesystem, and their effect on `stats()` | PASS 79/79 - [log](RT_rename_delete_tests.log) |
| [RT\_error\_paths\_tests.spin2](RT_error_paths_tests.spin2) | The `error()` contract, handle misuse, and the refusal of a bad `HANDLE_BASE` | PASS 241/241 - [log](RT_error_paths_tests.log) |
| [RT\_mount\_state\_tests.spin2](RT_mount_state_tests.spin2) | The mount state: the first mount with no free lock, `mounted()`, `can_mount()`, the handle pool, `unmount()` with writers open, and mount, unmount and format across cogs | PASS 33/33 - [log](RT_mount_state_tests.log) |
| [RT\_full\_flash\_tests.spin2](RT_full_flash_tests.spin2) | Fills the flash and checks every route to E\_DRIVE\_FULL, in a guard-only mode and a fixed mode | PASS 38/38 - [log](RT_full_flash_tests.log) |
| [RT\_power\_loss\_tests.spin2](RT_power_loss_tests.spin2) | The block states a power cut can leave, built straight on the flash, and an injected flash timeout at each step of a commit | PASS 163/163 - [log](RT_power_loss_tests.log) |
| [RT\_single\_handle\_smoke\_tests.spin2](RT_single_handle_smoke_tests.spin2) | A driver built with whatever `MAX_FILES_OPEN` it was given: a build with none refuses to mount, one with one or more works and holds every handle at once | PASS 12/12 - [log](RT_single_handle_smoke_tests.log) |
| [RT\_performance\_baseline.spin2](RT_performance_baseline.spin2) | Times the driver (not a pass/fail suite): 4 KB, 64 KB and 690 KB writes and reads, `open()` with 1, 50 and 100 files, a block-programming write, a far seek, `mount()`, `can_mount()` and `format()`, as a table in system clock ticks and µs with clkfreq stated | PASS 19/19, and the table - [log](RT_performance_baseline.log) |

## Test history

This is a recap of the version history of the older files:

| Date | Status |
| --- | --- |
|  <PRE>2023-Aug-26</PRE> | Initial release. `RT_read_write_tests.spin2`<br>Working Format, Mount, open(file, "R"), open(file, "W"), close(),<br>Focused tests for wr\_byte(), rd\_byte(), wr\_word(), rd\_word(), wr\_long(), rd\_long(), wr\_str(), and rd\_str() <br>Spanning blocks tests need to be added|
|  <PRE>2023-Aug-27</PRE> | More Tests: `RT_read_write_block_tests.spin2`<br>Focused tests for read(), write(), and file\_size_unused(): in only block, spanning two blocks, spanning 3 blocks |
|  <PRE>2023-Aug-28</PRE> | More Tests: `RT_read_seek_tests.spin2`<br>Focused tests for seek(): in only block, spanning two blocks, spanning 3 blocks |
|  <PRE>2023-Aug-29</PRE> | **Updated** `RT_read_write_tests.spin2`<br>Added tests for version(), serial_number(), directory(), and 2, 3 block span tests using longs |
|  <PRE>2023-Sep-02</PRE> | More Tests `RT_write_append_tests.spin2`<br>Focused tests for open(file, "A") with additional tests for 2, 3 block span tests using longs |
|  <PRE>2023-Sep-08</PRE> | More Tests `RT_mount_handle_basics_tests.spin2`<br>This tests all methods when filesystem is not mounted, when we are out of handles and when attempting to use an illegal handle |
|  <PRE>2023-Sep-08</PRE> | More Tests `RT_read_write_circular_tests.spin2`<br>The full suite exercising open_circular() for read and append. They use 1KB records with id and checksum in each so that the reads can be certified to start at the exact byte they should. |
|  <PRE>2023-Sep-12</PRE> | `RT_write_append_tests.spin2`: added testing of flush(). `RT_read_write_tests.spin2`: added testing of unmount() and mount() |
|  <PRE>2023-Sep-13</PRE> | More Tests `RT_read_seek_tests.spin2`<br>Added testing of seek()'s "current position relative" feature |
|  <PRE>2023-Sep-19</PRE> | More Tests `RT_read_write_8cog_tests.spin2`<br>Added testing of multi-cog support |
|  <PRE>2023-Dec-18</PRE> | Added Tests `RT_read_modify_write_tests.spin2`<br>Added testing of read/modify/write support ("r+" and "w+" open modes) |
|  <PRE>2023-Dec-19</PRE> | More Tests `RT_read_write_tests.spin2`<br>Added testing of create_file() method |
|  <PRE>2026-Nov</PRE> | The v2.1 programs: `RT_rmw_extended_tests`, `RT_seek_edge_tests`, `RT_boundary_size_tests`, `RT_rd_str_boundary_tests`, `RT_filename_tests`, `RT_rename_delete_tests`, `RT_error_paths_tests`, `RT_mount_state_tests`, `RT_full_flash_tests`, `RT_power_loss_tests`, `RT_single_handle_smoke_tests`, `RT_performance_baseline`; the shared helpers in `RT_utilities` and the runner `tools/run_tests.sh` |

### Next Steps:

- certify life-cycle changes for blocks of files created/modified (this is visually checked for now...)
- ...

---

> If you like my work and/or this has helped you in some way then feel free to help me out for a couple of :coffee:'s or :pizza: slices!
>
> [![coffee](https://www.buymeacoffee.com/assets/img/custom_images/black_img.png)](https://www.buymeacoffee.com/ironsheep) &nbsp;&nbsp; -OR- &nbsp;&nbsp; [![Patreon](../DOCs/images/patreon.png)](https://www.patreon.com/IronSheep?fan_landing=true)[Patreon.com/IronSheep](https://www.patreon.com/IronSheep?fan_landing=true)

---

## Disclaimer and Legal

> *Parallax, Propeller Spin, and the Parallax and Propeller Hat logos* are trademarks of Parallax Inc., dba Parallax Semiconductor
>
> This project is a community project not for commercial use.
>
> This project is in no way affiliated with, authorized, maintained, sponsored or endorsed by *Parallax Inc., dba Parallax Semiconductor* or any of its affiliates or subsidiaries.

---

## License

Licensed under the MIT License.

Follow these links for more information:

### [Copyright](copyright) | [License](LICENSE)

[maintenance-shield]: https://img.shields.io/badge/maintainer-stephen%40ironsheep%2ebiz-blue.svg?style=for-the-badge

[license-shield]: https://camo.githubusercontent.com/bc04f96d911ea5f6e3b00e44fc0731ea74c8e1e9/68747470733a2f2f696d672e736869656c64732e696f2f6769746875622f6c6963656e73652f69616e74726963682f746578742d646976696465722d726f772e7376673f7374796c653d666f722d7468652d6261646765
