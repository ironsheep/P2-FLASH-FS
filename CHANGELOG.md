# Changelog

## v2.1.0 (YYYY-MM-DD)

Every call reports its error, the file modes follow ANSI C except where the flash requires otherwise, and reads and writes move runs of bytes.

### Bug Fixes

- `"w"` and `"w+"` on an existing file, closed with no write, delete the file and return SUCCESS. The old file is no longer kept. `"a"` and `"r+"` closed with no write leave the file unchanged.
- `"w+"` on an existing file starts a new empty file and replaces the old one at `close()` or `flush()`. It no longer edits the old file in place, which kept its stale tail records. `exists()` and `file_size()` report the old file until then.
- `"r+"` grows the file when written at or past its end, and `rd_byte()` and `rd_str()` work on `"r+"` handles.
- A full flash returns E_DRIVE_FULL where it could write over the boot area. `close()` and `flush()` report it, and a `flush()` that finds no free block keeps the unwritten data for a later `flush()` or `close()`.
- `wr_word()`, `wr_long()` and `wr_str()` report a short write.
- `rd_long()` returns 0 when fewer than four bytes are read. Code that checks `error()` before using the value is unaffected; code that used the partial value now sees 0.
- `create_file()` with a count of 0 or less returns E_BAD_FILE_LENGTH and creates nothing, where it wrote an empty file.
- An empty name, a NULL pointer and a name of 128 or more characters return E_BAD_FILENAME from every call that takes a name.
- A flash chip that does not finish an erase or program returns E_FLASH_TIMEOUT and leaves the filesystem unmounted until `mount()`. The call no longer hangs.
- A double `close()`, and any call on a handle that is in range and not open, returns E_BAD_HANDLE. E_FILE_MODE now means an open handle in a mode the call does not serve.
- `unmount()` commits the data of files open for writing, closes every handle, and returns the first close failure.
- `mount()` reports E_BAD_BLOCKS_REMOVED for a cancelled bad-CRC block, and cancels a block whose ID, NextID, EndPtr or data offset is out of range. It removes a file whose chain names a block that cannot exist.
- `can_mount()` is TRUE when mounted. It is FALSE with SUCCESS for a duplicate ID alone, and FALSE with E_BAD_BLOCKS_REMOVED for a dead, bad-CRC or out-of-range block.
- `seek()` to POSX on an empty file gives 0, and `SK_CURRENT_POSN` counts from the handle's true file offset. For an old-format (v1.4) circular file read with `open_circular()`, seek positions and `file_size_for_handle()` count from the first byte the limit keeps.
- `file_size()` and `file_size_for_handle()` give a trimmed circular file's readable length. `file_size_for_handle()` on a `"w"` or `"a"` handle gives the file as the handle will commit it.
- `open_circular()` for read of a new-format file found after an old-format file no longer takes the old-format path.
- `directory()` sets the file size to 0 at the end of the list.
- `write()` returns the calling cog's error code, not cog 0's.
- `mount()`, `format()` and `can_mount()` return E_NO_HANDLE for a build with `MAX_FILES_OPEN` below 1 and E_BAD_HANDLE for a `HANDLE_BASE` that is not 0 or 1, before they touch the flash.

### New Features

- `HANDLE_BASE` (default 0) sets the value of the first handle, 0 or 1.
- New error codes: `E_BAD_FILENAME` (-20), `E_FLASH_TIMEOUT` (-21).
- A negative count to `read()`, `write()` or `rd_str()` returns E_BAD_FILE_LENGTH and transfers nothing.

### Improvements

- `read()`, `write()`, `rd_str()` and the typed `rd_` and `wr_` calls move runs of bytes in place of one byte per call. Figures, in system clock ticks and µs with the clkfreq stated:

  **[measured at bench visit 7: SPEEDUP_TABLE]**

  The SPI share of block-read time after this change: **[measured at bench visit 7: SPI_SHARE]**.
- Every call sets `error()` for the calling cog, on every path: SUCCESS, or the reason it failed.
- The hub lock is kept from the first `mount()` until power-down, and `unmount()` no longer returns it. Each call holds the lock from start to finish.
- E_FILE_WRITING (-5), E_FILE_READING (-6) and E_SHORT_TRANSER (-16) are reserved: the driver never returns them.

Compilers tested: **[measured at bench visit 10: TESTED_COMPILERS]**

### Known Issues

- `mount()` assumes no block ID is held by more than two blocks.
- A block moved to wear-level the flash is copied with a new CRC, and the CRC of the block being moved is not checked first, so a bit error in it is copied.
- Every call that reaches the flash takes over pins 58 to 61 and does not check whether another user of those pins, such as an SD card, holds them.
- The driver is certified at a 320 MHz system clock, the clock every regression run uses. The SPI timing has been verified up to 350 MHz, but only 320 MHz is certified.

## Earlier releases

The releases before v2.1.0, carried over from the driver header:

- v1.2.0 - initial release of flash_fs with full API
- v1.2.1 - revised seek() method parameters - can now seek relative to current position in file
- v1.3.0 - update for flexspin compatibility, seek() returns file position, write() returns bytes written
- v1.3.1 - more update for flexspin compatibility, adjusted seek(), read() and write() add file_size_for_handle()
- v1.4.0 - Adjustments allowing multi-cog support
- v2.0.0 - Add read/modify/write, non-destructive mount check can_mount(), and create_file()
