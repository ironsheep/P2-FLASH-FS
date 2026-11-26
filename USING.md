# P2-FLASH-FS - Using the Flash FS API
Flash FS - a filesystem for the FLASH chip on the P2 Edge Module.

![Project Maintenance][maintenance-shield]

[![License][license-shield]](LICENSE)

What each call does, where it differs from the C file API, and the modes beyond plain read and write: circular files, read-modify-write and multi-cog use. The method-by-method reference, with every parameter and error code, is [flash_fs.txt](flash_fs.txt).

## Table of Contents

On this Page:

- [Differences from ANSI C](#differences-from-ansi-c) - what each open mode does, and every place we differ from C, with the reason
- [Features of Note](#features-of-note) - circular files, read-modify-write, create_file()
- [Multi-cog use](#multi-cog-use) - the lock contract, and what it costs the other cogs
- [How to Contribute](#how-to-contribute) - you can contribute to this project

Additional pages:

- [README](README.md) - the top page of this project
- [Adding to Your Project](DEVELOP.md) - download, include, configure, mount, and a complete first program
- [Migrating](MIGRATING.md) - what a v2.0 or v1.4 program may notice in v2.1
- [The flash_fs Object I/F Documentation](flash_fs.txt) - the object interface with documentation for each public method
- [CHANGELOG](CHANGELOG.md) - the release history
- [SPI FLASH Datasheet](DOCs/W25Q128JV-210823.pdf) - our FLASH Chip Datasheet
- [FS Theory of Operations](THEOPSv2.md) - a detailed description of key concepts of this filesystem
- [v1.x FS Theory of Operations](THEOPS.md) - the v1 archive, kept for earlier versions
- [Memory Sizing Guide](DOCs/MEMORY-SIZING-GUIDE.md) - what the driver costs in hub RAM, measured with pnut-ts
- [SPI Performance Analysis](DOCs/SPI-PERFORMANCE-ANALYSIS.md) - where the time goes in a read, a write and a mount
- [Regression Testing Status](RegresssionTests/README.md) - regression test programs and their output logs
- [Test Coverage](RegresssionTests/COVERAGE.md) - which program checks which method and behavior
- [Contributing](CONTRIBUTING.md) - how to send a clean pull request

## Differences from ANSI C

The filesystem API follows the ANSI C file API, and where a call differs from C the difference is listed here with its reason. The driver's doc comments, and `flash_fs.txt` generated from them, state each call's own behavior; this page gathers the differences in one place.

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

In this example you see a file being limited to 8k bytes. This means keep track of the last 8k bytes worth of journal or log entries. Upon close the journal will be reduced to the requested limit. The file's size, as `file_size()` reports it, is the length you can read from it.

**NOTE:** *Remember to call `flash.flush(handle)` periodically so the pending writes stay small enough that you don't run out of flash space.*

An `open_circular(..., "r", 8_192)` is provided so that one can open the journal file and start reading at the front of the last 8_192 bytes in the file.

### Feature: File Read-Modify-Write

You can modify existing files on flash. Think of a file which contains fixed size records, maybe the state of an array of sensors where each sensor (or group of sensors) is in their own record within the file.

```spin2
    handle := flash.open(@"filename", %"r+")  ' alternatively use FILEMODE_READ_EXTENDED for %"r+"
    ... many reads and/or replacing writes ...
    status := flash.close(handle)
```

Open the file with the %"r+" mode, then seek to the record you wish to replace and write it (replacing the record already there.) Continue by seeking to locations and writing new records. Of course you can seek to and read the existing records, too. A write at or past the end of the file grows the file, as it does in C. Lastly close the file as normal.

We also provide an open mode of `flash.open(@"filename", %"w+")`. It starts a **new, empty file**, so you first have to write the new records before you can seek to them or replace them with new records. If a file of that name already exists, it is left whole, and still the file `exists()` and `file_size()` report, until the new file is committed by `flush()` or `close()`; then the new file replaces it in one step. A `"w+"` file closed without a write leaves no file at all: an existing file of that name is deleted. The [Differences from ANSI C](#differences-from-ansi-c) section lists every mode.

Lastly we've added a `flash.create_file()` method which you can use to create an initialized file with empty records. For example:

```spin2
    ' create empty file
    status := flash.create_file(@"filename", $00, 4_096)
    ' now do updates to the file
    handle := flash.open(@"filename", %"r+")
    ... many reads and/or replacing writes ...
    status := flash.close(handle)
```

In this example we are initializing a file with 4k bytes of zeros. You can use any byte value you wish for the fill value. The length must be at least 1: a length of 0 or less returns E_BAD_FILE_LENGTH and creates nothing.

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

How the lock works inside, and what a device fault leaves on the flash, is in [Locking](THEOPSv2.md#locking-how-cogs-share-the-filesystem-k) and [Device faults](THEOPSv2.md#device-faults-d) of the Theory of Operations.

## How to Contribute

This is a project supporting our P2 Development Community. Please feel free to contribute to this project. You can contribute in the following ways:

- File **Feature Requests** or **Issues** (describing things you are seeing while using our code) at the [Project Issue Tracking Page](https://github.com/ironsheep/P2-FLASH-FS/issues)
- Fork this repo and then add your code to it. Finally, create a Pull Request to contribute your code back to this repository for inclusion with the projects code. See [CONTRIBUTING](CONTRIBUTING.md)

---

> If you like my work and/or this has helped you in some way then feel free to help me out for a couple of :coffee:'s or :pizza: slices!
>
> [![coffee](https://www.buymeacoffee.com/assets/img/custom_images/black_img.png)](https://www.buymeacoffee.com/ironsheep) &nbsp;&nbsp; -OR- &nbsp;&nbsp; [![Patreon](./DOCs/images/patreon.png)](https://www.patreon.com/IronSheep?fan_landing=true)[Patreon.com/IronSheep](https://www.patreon.com/IronSheep?fan_landing=true)

---

## Disclaimer and Legal

> *Parallax, Propeller Spin, and the Parallax and Propeller Hat logos* are trademarks of Parallax Inc., dba Parallax Semiconductor
>
> This project is in no way affiliated with, authorized, maintained, sponsored or endorsed by *Parallax Inc., dba Parallax Semiconductor* or any of its affiliates or subsidiaries.

---

## License

Licensed under the MIT License.

Follow these links for more information:

### [Copyright](copyright) | [License](LICENSE)

[maintenance-shield]: https://img.shields.io/badge/maintainer-stephen%40ironsheep%2ebiz-blue.svg?style=for-the-badge

[license-shield]: https://img.shields.io/badge/License-MIT-yellow.svg
