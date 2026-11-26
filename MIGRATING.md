# P2-FLASH-FS - Migrating to a new release
Flash FS - a filesystem for the FLASH chip on the P2 Edge Module.

![Project Maintenance][maintenance-shield]

[![License][license-shield]](LICENSE)

This page is for programs that already use an earlier release of the driver. If you are starting a new project, you do not need it: start at [Adding to Your Project](DEVELOP.md).

## Table of Contents

On this Page:

- [Migration from v2.0 to v2.1](#migration-from-v20-to-v21) - what a v2.0 program may notice
- [Migration from v1.4 to v2.0](#migration-from-v14-to-v20) - circular files

Additional pages:

- [README](README.md) - the top page of this project
- [Adding to Your Project](DEVELOP.md) - download, include, configure, mount, and a complete first program
- [Using the API](USING.md) - the open modes, how we differ from C, circular files, read-modify-write and multi-cog use
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

## Migration from v2.0 to v2.1

A program that relies on what v2.0 documented keeps working. The changes below are a program's visible difference, in two groups: fixes, where v2.0 did something other than what it documented or what C does, and additions. The one return-value change is `rd_long()` on its error path (item 9).

### Behavior fixes

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
- `HANDLE_BASE` (default 0): the value of the first handle. See [Configuring the driver](DEVELOP.md#step-3-configuring-the-driver).
- The hub lock is held from the first `mount()` until power-down, and `unmount()` no longer returns it, so the driver keeps one of the P2's 16 hub locks for the life of the run. See [Multi-cog use](USING.md#multi-cog-use).
- The `create_file()` doc comment now lists E_BAD_FILE_LENGTH.
- E_FILE_WRITING (-5), E_FILE_READING (-6) and E_SHORT_TRANSER (-16) are reserved: the driver never returns them. Their values stay so the numbering of the other codes does not change.

## Migration from v1.4 to v2.0

There is NO migration needed if you are **not using Circular Files**.

If you are using Circular files and you need to preserve them instead of just creating new ones, then you will first want to copy your existing circular file to a new one. This creates the new file head block supporting circular seeks.

Example copy file code:

```spin2
PUB exampleCopy(pOldFilename, pNewFilename) | status, rdHandle, rdLength, wrHandle, rdStatus, wrStatus, wrLength

    ' abort if there is no file to copy
    ifnot flash.exists(pOldFilename)
        debug("Abort: no file to copy")
        return

    ' remove the new file if it already exists
    if flash.exists(pNewFilename)
        status := flash.delete(pNewFilename)

    ' open existing file in basic "read" mode
    rdHandle := flash.open(pOldFilename, "r")
    ' open new file with exact circular length of your original file
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
