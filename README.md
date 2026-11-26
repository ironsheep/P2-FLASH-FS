# P2-FLASH-FS
Flash FS - a filesystem for the FLASH chip on the P2 Edge Module.

![Project Maintenance][maintenance-shield]

[![License][license-shield]](LICENSE)

The following files can be found at the top level of this repository:

| Key Files | Description |
| --- | --- |
| [`flash_fs.spin2`](./flash_fs.spin2) | The complete FLASH driver object
| [`flash_fs.txt`](./flash_fs.txt) | Object Interface Document for the FLASH driver
| [`CHANGELOG.md`](./CHANGELOG.md) | What changed in each release
| [`cgsm_flash_file_demo.zip`](./cgsm_flash_file_demo.zip) | Jon McPhalens latest Interactive Filesystem Demo
| [`flash_fs_demo.spin2`](./flash_fs_demo.spin2) | Chip's original light-weight non-interactive demo

## Table of Contents

On this Page:

- [Flash Filesystem Features](#flash-filesystem-features) - key features of this filesystem / design goals
- [Features of Note](#features-of-note) - circular files, read-modify-write, create_file()
- [Differences from ANSI C](#differences-from-ansi-c) - what each open mode does, and every place we differ from C, with the reason
- [Configuring the driver](#configuring-the-driver) - MAX_FILES_OPEN, HANDLE_BASE, the limits, and what a handle costs
- [Multi-cog use](#multi-cog-use) - the lock contract, and what it costs the other cogs
- [Migration from v2.0 to v2.1](#migration-from-v20-to-v21) - what a v2.0 program may notice
- [Migration from v1.4 to v2.0](#migration-from-v14-to-v20) - circular files
- [Known limits](#known-limits) - what the driver does not check
- [Adding the flash fs to your own project](#adding-the-flash-fs-to-your-own-project)
- [Contributing](#how-to-contribute) - you can contribute to this project

Additional pages:

- [The flash_fs Object I/F Documentation](flash_fs.txt) - the object interface with documentation for each public method
- [CHANGELOG](CHANGELOG.md) - the release history
- [SPI FLASH Datasheet](./DOCs/W25Q128JV-210823.pdf) - our FLASH Chip Datasheet
- [FS Theory of Operations](THEOPSv2.md) - a detailed description of key concepts of this filesystem (See [v1.x FS Theory of...](THEOPS.md) for earlier version)
- [Memory Sizing Guide](./DOCs/MEMORY-SIZING-GUIDE.md) - what the driver costs in hub RAM, measured with pnut-ts
- [SPI Performance Analysis](./DOCs/SPI-PERFORMANCE-ANALYSIS.md) - where the time goes in a read, a write and a mount
- [Regression Testing Status](./RegresssionTests) - regression test code and output logs, certified for each release (v2.1.0: 21 programs, 2,126 tests, all passing)

## Flash Filesystem Features

Key features of this Flash Filesystem for the P2 Edge Flash chip:

- Wear-leveling write mechanism
- Writes are structured to facilitate recovery of file structure after unplanned power failure
- Block identification is independent of a block's physical location
- Filenames are 1 to 127 characters (plus the zero terminator)
- Seeks supported
- File Append supported
- Read-Modify-Write supported
- Circular file writes supported
- Supports multi-cog use (the first cog to call mount() mounts the filesystem for all cogs to use; each call holds one lock from start to finish, see [Multi-cog use](#multi-cog-use))
- Fast bulk transfers: `read()`, `write()`, `rd_str()` and `wr_str()` move runs of bytes, not one byte per call. The before-and-after timings are tabled in [CHANGELOG.md](CHANGELOG.md) and, in clock ticks, in [DOCs/SPI-PERFORMANCE-ANALYSIS.md](DOCs/SPI-PERFORMANCE-ANALYSIS.md)
- Handle numbers count from 0 (the default) or from 1 (`HANDLE_BASE`), see [Configuring the driver](#configuring-the-driver)
- `error()` is kept per cog and holds the reason for the last failed call
- **Coming soon** *Directory Support*

## Features of Note

In addition to standard file operations this filesystem contains a couple features worth noting:

### Feature: Circular files

Circular files are useful when you want to record the most recent journal entries (or event log entries) in a file.

One writes to circular files by appending to them. At file open, one specifies a maximum limit to the file size in bytes, for example:

```spin2
    handle := flash.open_circular(@"filename", "a", 8_192)
    ... many writes ...
    status := flash.close(handle)
```

In this example you see a file being limited to 8k bytes.  This means keep track of the last 8k bytes worth of journal or log entries.  Upon close the journal will be reduced to the requested limit. The file's size, as `file_size()` reports it, is the length you can read from it.

NOTE: Remember to call `flash.flush(handle)` periodically to keep the pending writes small enough so that you don't run out of flash space.

An `open_circular(..., "r", 8_192)` is provided so that one can open the journal file and start reading at the front of the last 8_192 bytes in the file.

### Feature: File Read-Modify-Write

You can modify existing files on flash.  Think of a file which contains fixed size records, maybe the state of an array of sensors where each sensor (or group of sensors) is in their own record within the file.

```spin2
    handle := flash.open(@"filename", %"r+")  ' alternatively use FILEMODE_READ_EXTENDED for %"r+"
    ... many  reads and/or replacing writes  ...
    status := flash.close(handle)
```

Open the file with the %"r+" mode, then seek to the record you wish to replace and write it (replacing the record already there.)  Continue by seeking to locations and writing new records. Of course you can seek to and read the existing records, too.  A write at or past the end of the file grows the file, as it does in C. Lastly close the file as normal.

We also provide an open mode of `flash.open(@"filename", %"w+")`. It starts a **new, empty file**, so you first have to write the new records before you can seek to them or replace them with new records. If a file of that name already exists, it is left whole, and still the file `exists()` and `file_size()` report, until the new file is committed by `flush()` or `close()`; then the new file replaces it in one step. A `"w+"` file closed without a write leaves no file at all: an existing file of that name is deleted. The [Differences from ANSI C](#differences-from-ansi-c) section lists every mode.

Lastly we've added a `flash.create_file()` method which you can use to create an initialized file with empty records.  For example:

```spin2
    ' create empty file
    status := flash.create_file(@"filename", $00, 4_096)
    ' now do updates to the file
    handle := flash.open(@"filename", %"r+")
    ... many  reads and/or replacing writes  ...
    status := flash.close(handle)
```

In this example we are initializing a file with 4k bytes of zeros.  You can use any byte value you wish for the fill value. The length must be at least 1: a length of 0 or less returns E_BAD_FILE_LENGTH and creates nothing.

## Differences from ANSI C

The filesystem API follows the ANSI C file API, and where a call differs from C the difference is listed here with its reason. This section is the one canonical copy; `flash_fs.txt` and the method doc comments point to it.

Most of the differences come from three facts about the flash:

- A file exists when its head block is on the flash, and a head block is a 4 KB erase and program. Nothing reaches the flash until a handle has been written, so there is **no empty file**: a file with no contents has no directory entry and no name.
- A block can only be erased and rewritten whole. A file being replaced is kept until the new one is committed, so a power cut leaves the old file or the new one and never a half-written file.
- The writes of a `"w"`, `"a"` or `"w+"` handle are held as a commit chain that is activated as one unit when you `flush()` or `close()`.

### What each open mode does

For every open mode this table says what happens at open, at a write, at `flush()` or `close()` after writes, and at `close()` with no writes. "No writes" means no `write()`, `wr_byte()`, `wr_word()`, `wr_long()` or `wr_str()` moved a byte (a `write()` of 0 bytes moves none). `close()` returns SUCCESS in every row of the last column, and so does `error()`.

| Mode | File | At open | After writes, at `flush()` or `close()` | `close()` with no writes |
| --- | --- | --- | --- | --- |
| `"r"` | does not exist | E_FILE_NOT_FOUND, no handle | - | - |
| `"r"` | exists | handle at byte 0; a write gives E_FILE_MODE | nothing to commit | file unchanged |
| `"w"` | does not exist | handle; nothing is on the flash, `exists()` is FALSE | the file appears and holds what was written; after `flush()` the handle stays open and later writes extend the file | **no file is created** |
| `"w"` | exists | handle; the old file is untouched and `exists()` and `file_size()` still report it | the old file is replaced by what was written; after `flush()` the handle stays open and later writes extend the new file | **the old file is deleted** |
| `"a"` | does not exist | the same as `"w"` on a file that does not exist | the same as `"w"` on a file that does not exist | **no file is created** |
| `"a"` | exists | handle; writes go to the end of the file | the file is the old contents plus what was appended | file unchanged |
| `"r+"` | does not exist | E_FILE_NOT_FOUND, no handle | - | - |
| `"r+"` | exists | handle at byte 0; read, seek and write anywhere; a write that runs past the end overwrites up to the end, then grows the file | each modified block is written back as the handle leaves it, and at `flush()` and `close()`; the file is modified in place | file unchanged |
| `"w+"` | does not exist | handle to a new, empty file; you can read and seek only over bytes you have written (a read before any write returns 0 bytes with `error()` E_END_OF_FILE) | the file appears and holds what was written; after `flush()` the handle stays open at the same position and later writes extend the file | **no file is created** |
| `"w+"` | exists | handle to a new, empty file; the old file is untouched and `exists()` and `file_size()` still report it | the old file is replaced by the new file in one step; after `flush()` the handle stays open at the same position and later writes extend the file | **the old file is deleted** |

Four consequences:

- To keep an existing file, do not open it with `"w"` or `"w+"`. Use `exists()` first. To add to it, use `"a"`; to change it in place, use `"r+"`.
- A `"w"` or `"w+"` file you close without writing is gone. `close()` does not warn you, because it did what you asked. Check with `exists()` when you need to know.
- `file_size()` and `exists()` see the file as it is on the flash. `file_size_for_handle()` also counts the bytes the handle holds and has not yet committed.
- The modes are `"r"`, `"w"`, `"a"`, `"r+"` and `"w+"`, in upper or lower case. Anything else, including `"a+"`, returns E_FILE_MODE. `open_circular()` takes `"r"` and `"a"` only.

### Where we differ from C

| Area | ANSI C | flash_fs | Flash reason |
| --- | --- | --- | --- |
| No empty files: `"w"` and `"w+"` closed with no writes | `fopen` truncates the file to length 0 and leaves it, empty | An existing file is deleted at `close()`, a new file is not created; `close()` returns SUCCESS. `create_file()` with a length of 0 or less returns E_BAD_FILE_LENGTH and creates nothing | A file exists when its head block is on the flash, and that block is only written when there is data to commit |
| When `"w"` and `"w+"` replace a file | The old contents are gone at `fopen` | The old file stays whole until `flush()` or `close()` commits the new one | A block cannot be changed in place without an erase; keeping the old file makes the replace a single activation, so a power cut leaves one file or the other |
| Seek past the end, then write | Allowed; the gap reads as zeros | The seek itself returns E_FILE_SEEK and leaves the position where it was. `seek(handle, POSX, SK_FILE_START)` goes to the end of the file, and a write there extends it | A file is a chain of blocks with no holes; a gap would have to be written out as fill |
| `r+` reads | `fgetc` and `fgets` work on a `r+` stream | `read()`, `rd_byte()`, `rd_word()`, `rd_long()` and `rd_str()` work on a `"r+"` handle (v2.0 refused `rd_byte()` and `rd_str()` with E_FILE_MODE) | No difference from C |
| `r+` writes at the end | A write at the end extends the file | The same: a write at or past the end grows the file | No difference from C |
| Seek on `"w"` and `"a"` handles | `fseek` is allowed | E_FILE_MODE: only `"r"`, `"r+"` and `"w+"` handles seek | The writes of these handles are one commit chain that is built at the end of the file |
| Reading a `"w"` or `"a"` handle, writing an `"r"` handle | An error (the stream is not open for it) | E_FILE_MODE | The same as C |
| A file already open | A second `fopen` of the same name is allowed | `open()` returns E_FILE_OPEN. `delete()`, `rename()` and `create_file()` of an open file return E_FILE_OPEN too | Each handle holds a block of the file in its own buffer; two handles would write two versions of the same block |
| Filename length | Up to the system's `PATH_MAX` | 1 to 127 characters. An empty name, a NULL pointer or a name of 128 or more characters returns E_BAD_FILENAME from every call that takes a name | The name sits in a fixed 128-byte field of the head block |
| `a+` | Opens for reading and appending | There is no `a+`: E_FILE_MODE. Use `"r+"`, which reads and writes, and `seek(handle, POSX, SK_FILE_START)` to go to the end | An append handle builds new blocks that are activated as one unit, so it keeps no read position in the file |
| `fflush` | Writes the stream's buffer to the file | `flush()` commits everything written so far, as `close()` would, and keeps the handle. Each flush that writes costs a block erase and program, so flush at record boundaries, not per byte | A commit is a block erase and program, and the flash wears with each one |
| `errno` | One per thread, set by a failing call | `error()` is kept per cog and every filesystem call sets it, to SUCCESS or the reason. `error()`, `string_for_error()`, `null()` and `mounted()` leave it alone. A call made by another cog never changes what your cog reads | The driver is shared by up to 8 cogs |
| Return values | `EOF`, `NULL` or -1 on failure | A negative code in place of the result for calls whose results are never negative (a handle, a size, a position, a byte); a count for `read()` and `rd_str()`, with `error()` holding the reason a count came up short (0 with E_FILE_MODE or E_BAD_HANDLE when the call could not start); `write()` returns the count written, or the negative code when it wrote nothing; `rd_long()` returns 0 on failure, so check `error()`. A handle that is out of range, or in range and not open, gives E_BAD_HANDLE from every call that takes one | Codes are specific, and a `LONG` result can legitimately be negative |
| Locking | Each call on a `FILE` takes that stream's lock | One lock for the whole filesystem, held for the whole call. See [Multi-cog use](#multi-cog-use) | All files share the tables, the block buffers and the one flash chip |

## Configuring the driver

The constants below are overridden where you include the driver, on the `OBJ` line. The compiler checks none of the values: `mount()`, `format()` and `can_mount()` check `MAX_FILES_OPEN` and `HANDLE_BASE` when they run, before they take the lock or touch the flash.

```spin2
OBJ { Objects Used by this Object }

    flash  : "flash_fs" | MAX_FILES_OPEN = 4, HANDLE_BASE = 1    ' the Flash Filesystem
```

| Constant | Default | Valid values | What it sets |
| --- | --- | --- | --- |
| `MAX_FILES_OPEN` | 2 | 1 or more | The number of files that can be open at one time, which is the number of handles. Each handle takes **4,264 bytes** of hub RAM, so the default build holds 8,528 bytes of handle state. Below 1, `mount()`, `format()` and `can_mount()` return E_NO_HANDLE |
| `HANDLE_BASE` | 0 | 0 or 1 | The value of the first handle `open()` returns. The handles are `HANDLE_BASE` to `HANDLE_BASE + MAX_FILES_OPEN - 1`, and every method that takes a handle takes one of these. Any other value makes `mount()`, `format()` and `can_mount()` return E_BAD_HANDLE |
| `FIRST_BLOCK` | `$080` | | The first 4 KB block of the flash the filesystem uses. The default leaves the first 512 KB for the boot image |
| `LAST_BLOCK` | `$FFF` | | The last block it uses. `LAST_BLOCK - FIRST_BLOCK + 1` can be no more than 4,095 blocks: a block ID is a 12-bit field, and the driver keeps one more value for its own use |

These are not constants to override:

- A file name is at most 127 characters (a zero terminator follows it).
- The driver serves at most 8 cogs at once.

**The per-handle figure.** 4,264 bytes is the growth of the driver's image for one more handle (the pnut-ts listing, `-l`, of the driver built with `MAX_FILES_OPEN` of 2 and of 3): the 4,096-byte block buffer, the 128-byte filename and 40 bytes of state. [MEMORY-SIZING-GUIDE](./DOCs/MEMORY-SIZING-GUIDE.md) shows how to measure it for your own build.

**The handle convention.** `open()` and `open_circular()` return a handle, or a negative error code in its place. With the default `HANDLE_BASE` of 0, handle 0 is a good handle, so test a result with `< 0` and not `== 0`. A program that counts handles from 1, a FemtoBasic program for example, sets `HANDLE_BASE = 1`. A handle outside the range, or one that is in range and not open, returns E_BAD_HANDLE from every method that takes a handle.

## Multi-cog use

Every cog that has the object can call it. The first `mount()` of the run (or `format()` or `can_mount()`) creates the driver's lock; if several cogs call at about the same moment they hold an election, which makes the first call take at least 10 ms. After that, one lock covers the whole filesystem:

- **Each call is exclusive.** A call takes the lock, does all its work, and releases it. No other cog's call runs in between, so a call never sees another call half done. Your program still has to order its own calls: the lock serializes calls, not your sequence of them.
- **A long call delays the other cogs.** A long `write()`, `create_file()`, `format()` or a `close()` that commits a circular file holds the lock for as long as it takes, and every other cog's call waits. The delay is about 55 to 59 ms for each 4 KB the call writes (a block erase and program), measured at 320 MHz.
- **Waiting cogs spin.** A cog waiting for the lock repeats `locktry()` in a loop. It does not sleep, and it does nothing else meanwhile.
- **No fairness is claimed.** The driver keeps no queue. Which waiting cog gets the lock next is up to the hardware, and a cog could wait through several other cogs' calls. The longest wait we have observed is 252,513 µs (about a quarter of a second) at 320 MHz: one `wr_str()` or `rd_str()` call in the 8-cog stress test, waiting while other cogs' calls ran. It differs from run to run; four runs gave 149,788 to 252,513 µs.
- **If you need bounded latency, write in chunks.** Each call to `write()` is its own lock hold. A cog that writes 4 KB at a time lets the other cogs in between the chunks, where one 100 KB call would hold them out for the whole of it.
- **One hub lock, for the life of the run.** The lock is kept from the first `mount()` until reset or power-off. `unmount()` does not return it, and a call another cog makes after it returns E_NOT_MOUNTED. The driver uses exactly one of the P2's 16 hub locks, and `mount()` returns E_NO_LOCK_AVAIL when none is free.
- **A device fault is handled as a power loss.** When the flash chip does not finish an erase or program in time, the call that hit it returns E_FLASH_TIMEOUT and the filesystem is left unmounted. The data every open file held and had not yet committed is lost, as at a power cut, in every file and for every cog. Every later call returns E_NOT_MOUNTED until a cog calls `mount()`, which rebuilds the state from the flash.

```spin2
PRI writeChunks(handle, pData, byteCount) : status | offset, chunkSize
    ' write byteCount bytes, 4 KB per call, so the other cogs can use the filesystem between calls
    status := flash.SUCCESS
    offset := 0
    repeat while offset < byteCount and status == flash.SUCCESS
      chunkSize := 4_096 <# (byteCount - offset)
      flash.write(handle, pData + offset, chunkSize)
      status := flash.error()
      offset += chunkSize
```

## Migration from v2.0 to v2.1

A program that relies on what v2.0 documented keeps working. The changes below are a program's visible difference, in two groups: fixes, where v2.0 did something other than what it documented or what C does, and additions. The one return-value change is `rd_long()` on its error path (item 9).

### Behaviour fixes

1. `"w"` and `"w+"` on an existing file, closed without writes, delete the file, where v2.0 kept it. `close()` returns SUCCESS and `error()` is SUCCESS: the program asked for an empty file, and the filesystem keeps none. Use `exists()` to confirm. A new file closed without writes is not created, as before.
2. `"w+"` on an existing file starts an empty file and replaces the old one when the new one is committed, at `close()` or `flush()`, where v2.0 edited the old file in place (and kept its stale tail records). Until the commit, `exists()` and `file_size()` of the name report the old file.
3. `create_file(..., byte_count)` with a count of 0 or less returns E_BAD_FILE_LENGTH and creates nothing, where v2.0 wrote an empty file.
4. `close()` and `flush()` report their errors, `can_mount()` is TRUE when the filesystem is mounted, and a full drive returns E_DRIVE_FULL, where v2.0 could write blocks over the boot area. A `"w"` or `"a"` writer fills a block only while a spare block is left for the block after it, so for a new file E_DRIVE_FULL comes from `write()` and `close()` always has room to commit. A writer that replaces or appends to an existing file can still get E_DRIVE_FULL from `close()` if other writes have used the free blocks since it was opened.
5. `wr_word()`, `wr_long()` and `wr_str()` report a short write, where v2.0 returned SUCCESS.
6. `"r+"` grows the file when it is written at or past its end, as C does. The v2.0 notes promised this.
7. An empty name, a NULL pointer and a name of 128 or more characters return E_BAD_FILENAME from every call that takes a name, where v2.0 mishandled them.
8. A device failure (E_FLASH_TIMEOUT) leaves the filesystem unmounted until `mount()` is called, where v2.0 hung forever.
9. `rd_long()` returns 0 when it fails, where v2.0 returned the bytes it had read. This is the one return-value change in the release, and it is on the error path only: the v2.0 doc comment already said to check `error()` for SUCCESS before using the value.
10. `mount()` reports E_BAD_BLOCKS_REMOVED for a cancelled bad-CRC block too, where v2.0 cancelled such a block without reporting it.
11. `seek()`: the end of an empty file is position 0, and `SK_CURRENT_POSN` counts from the handle's true file offset.
12. `directory()` sets the file size to 0 at the end of the list, where v2.0 left the size holding the previous call's value.
13. `write()` returns the calling cog's error code, where v2.0 could return cog 0's.
14. A double `close()`, or `close()` or `flush()` of a handle that is not open, returns E_BAD_HANDLE. So does `file_size_for_handle()` for an out-of-range or closed handle. Every method that takes a handle (`seek()`, `read()`, `write()` and the `wr_` and `rd_` calls) returns E_BAD_HANDLE for a handle in range that is not open, where v2.0 returned E_FILE_MODE from several. E_FILE_MODE now means a handle that is open in a mode the method does not serve.
15. `unmount()` commits the data of files open for writing before it frees their handles, where v2.0 freed the handle first and the data was lost. It returns the first close failure and still closes every handle.
16. `mount()`, `format()` and `can_mount()` check `MAX_FILES_OPEN` (1 or more) and `HANDLE_BASE` (0 or 1) when they run, and return E_NO_HANDLE or E_BAD_HANDLE for a build outside them before they touch the flash.
17. A `flush()` that cannot commit for lack of a free block keeps the unwritten data and the handle, so a later `flush()` or `close()` commits it once a block is free. A `close()` retries the trim of a circular file that a `flush()` could not make.
18. `can_mount()` is FALSE with `error()` SUCCESS for a duplicate block ID alone (a `mount()` resolves it and returns SUCCESS), and FALSE with E_BAD_BLOCKS_REMOVED for a dead block, a bad-CRC block, or one with an out-of-range field.
19. `mount()` cancels a block whose ID, NextID, EndPtr or data offset is out of range, and removes a file whose chain names a block that cannot exist, where v2.0 trusted those fields.
20. `file_size()` and every size call give a trimmed circular file's readable length, where v2.0 counted the bytes the trim had dropped from the first kept block.
21. `file_size_for_handle()` on a handle open with `"w"` or `"a"` gives the file as the handle will commit it, and `seek()` and the size calls count bytes written and not yet flushed.
22. `SK_CURRENT_POSN` and `file_size_for_handle()` on an old-format (v1.4) circular file opened for read count from the start of the window the limit keeps.
23. `open_circular()` for read of a new-format file, found after an old-format file in the same flash, no longer takes the old-format path.

### Additions and new limits

These are not fixes; each is new in v2.1 or a limit you may meet.

- Two new error codes: `E_BAD_FILENAME` (-20) and `E_FLASH_TIMEOUT` (-21). Existing codes keep their values.
- A negative count to `read()`, `write()` or `rd_str()` returns E_BAD_FILE_LENGTH and transfers nothing.
- `HANDLE_BASE` (default 0): the value of the first handle. See [Configuring the driver](#configuring-the-driver).
- The hub lock is held from the first `mount()` until power-down, and `unmount()` no longer returns it, so the driver keeps one of the P2's 16 hub locks for the life of the run. See [Multi-cog use](#multi-cog-use).
- The `create_file()` doc comment now lists E_BAD_FILE_LENGTH.
- E_FILE_WRITING (-5), E_FILE_READING (-6) and E_SHORT_TRANSER (-16) are reserved: the driver never returns them. Their values stay so the numbering of the other codes does not change.

## Migration from v1.4 to v2.0

There is NO migration needed if you are **not using Circular Files**.

If you are using Circular files and you need to preserve them instead of just creating new ones, then you will first want to copy your existing circular file to a new one. This creates the new file head block supporting circular seeks.

Example copy file code:

```spin2
PUB exampleCopy(pOldFilename, pNewFilename) | status, rdHandle, rdLength, wrHandle, rdStatus, wrStatus, wrLength

    ' remove existing file if it exists
    if flash.exists(pNewFilename)
      status := flash.delete(pNewFilename)

    ifnot flash.exists(pNewFilename)
        debug("Abort: no file to copy")

    ' open existng file in basic "read" mode
    rdHandle := flash.open(pOldFilename, "r")
    ' open new file with exact circular length of your orignal file
    wrHandle := flash.open_circular(pNewFilename, "a", CIRCULAR_LEN_IN_BYTES)

    repeat
      rdLength := flash.read(rdHandle, @record, RECORD_LEN)
      rdStatus := flash.error()
      if rdStatus <> flash.SUCCESS and rdStatus <> flash.E_END_OF_FILE
        debug("Abort: read error")
        quit

      wrLength := flash.write(wrHandle, @record, rdLength)
      wrStatus := flash.error()
      if wrStatus <> flash.SUCCESS
        debug("Abort: write error")
        quit

      if rdStatus == flash.E_END_OF_FILE
         debug("DONE: copy complete")
        quit

    while wrStatus == flash.SUCCESS
    ' and close our files
    flash.close(rdHandle)
    flash.close(wrHandle)

```

## Known limits

The driver does not check or handle these. They are also listed in the driver's header.

- **Two copies of an ID, at most.** A power loss part-way through moving a block leaves two blocks with one ID, and `mount()` resolves the pair by keeping the newer. It assumes no ID is held by more than two blocks.
- **Moving a block does not check its CRC first.** When the driver moves a block to wear-level the flash, it copies the data and computes a new CRC over the copy. The CRC of the block being moved is not checked, so a bit error in it is copied into a block that then looks good.
- **Pins 58 to 61 are taken on every call.** Every call that reaches the flash drives the flash chip's pins and does not check whether another user of those pins (an SD card, for example) holds them.
- **The driver is certified at a 320 MHz system clock.** Every regression run uses 320 MHz. The SPI timing has been verified up to 350 MHz, but 320 MHz is the clock this release is certified for.

## Adding the Flash FS to your own project

This section describes how to quickly get the flash filesystem working in your project.

### Download the latest flash_fs.spin2 file

Every time you wish to start a project using the flash filesystem you will want to download the latest version from the repository [ironsheep/P2-FLASH-FS](https://github.com/ironsheep/P2-FLASH-FS). In the list of files on the top page you will see the file `flash_fs.spin2`. You can download this single file to get the latest or you can navigate to the [releases](https://github.com/ironsheep/P2-FLASH-FS/releases) page where you can download the latest release which includes demo files as well as the filesystem object.

### Include the Flash FS object in your top file

Place the downloaded `flash_fs.spin2` in your project and in your top-level object include the flash object:

```spin2
OBJ { Objects Used by this Object }

    flash  : "flash_fs"    ' the Flash Filesystem
```

The driver keeps 4,264 bytes per open file. The space is allocated for two open files by default.  You can override this in your top-level file by changing the include to something like:

```spin2
OBJ { Objects Used by this Object }

    flash  : "flash_fs" | MAX_FILES_OPEN = 4    ' the Flash Filesystem
```

In this case we are telling the compiler to allocate room for 4 simultaneously accessible files instead of the default two files. [Configuring the driver](#configuring-the-driver) lists the other constants you can override.

### Format() or Mount() the flash filesystem

At the start of your application you will need to mount() the filesystem.

```spin2
PRI main() | status

    status := flash.mount()	           ' start up the FLASH filesystem
    if status <> flash.SUCCESS
      '... you know that some blocks were corrupted and freed ...
```

`mount()` returns E_BAD_BLOCKS_REMOVED when it cancelled blocks that were damaged or that no file reached; the filesystem is mounted and usable either way. Other codes (E_NO_LOCK_AVAIL, E_FLASH_TIMEOUT) mean it is not mounted.

If you know that that the flash chip in your P2 Edge module has never been formatted then you can call format instead of mount. (The format will then do the mount for you.)

```spin2
PRI main()

    flash.format()	           ' start up the FLASH filesystem
```

### Work with files on flash as you would normally

Now that your filesystem is mounted you are free to do normal file operations. The filesystem API is very similar to the ANSI-C file handling API so this all should feel pretty natural to you. Where it differs, [Differences from ANSI C](#differences-from-ansi-c) says how and why.

Review the [Flash F/S Object I/F Documentation](flash_fs.txt) then start reading and writing files!

Please Enjoy!
*Stephen*

## How to Contribute

This is a project supporting our P2 Development Community. Please feel free to contribute to this project. You can contribute in the following ways:

- File **Feature Requests** or **Issues** (describing things you are seeing while using our code) at the [Project Issue Tracking Page](https://github.com/ironsheep/P2-FLASH-FS/issues)
- Fork this repo and then add your code to it. Finally, create a Pull Request to contribute your code back to this repository for inclusion with the projects code. See [CONTRIBUTING](CONTRIBUTING.md)

## Credits

Thank you to **Chip Gracey** for the excellent **Flash File System 16MB** written for the P2 which is the core of this filesystem.

Thank you to **Jon McPhalen** for helping to specify the customer facing API for this filesystem and for guidance in our future directions for the upcoming dual filesystem driver as well.  Jon also contributed his interactive filesystem demo.

Thank you also to members of the [forum thread - "On-Board Flash File System"](https://forums.parallax.com/discussion/175470/on-board-flash-file-system#latest) for also contributing ideas and guidance for implementation of this driver.

---

> If you like my work and/or this has helped you in some way then feel free to help me out for a couple of :coffee:'s or :pizza: slices!
>
> [![coffee](https://www.buymeacoffee.com/assets/img/custom_images/black_img.png)](https://www.buymeacoffee.com/ironsheep) &nbsp;&nbsp; -OR- &nbsp;&nbsp; [![Patreon](./DOCs/images/patreon.png)](https://www.patreon.com/IronSheep?fan_landing=true)[Patreon.com/IronSheep](https://www.patreon.com/IronSheep?fan_landing=true)

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


[license-shield]: https://img.shields.io/badge/License-MIT-yellow.svg
