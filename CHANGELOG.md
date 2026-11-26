# Changelog

## v2.1.0 (2026-11-26)

Every call reports its error, the open modes behave as documented, and `read()` and `write()` are faster.

### New Features

- `HANDLE_BASE` (default 0) sets the first handle to 0 or 1, from the caller's OBJ line
- New error codes: `E_BAD_FILENAME` (-20), `E_FLASH_TIMEOUT` (-21)

### Improvements

- Reads, writes and the typed calls are faster, except `rd_byte()` and `wr_byte()`:

  | Operation | v2.0.0 | v2.1.0 | Change |
  | --- | ---: | ---: | --- |
  | `read()` of a 4 KB file | 36.6 ms | 1.2 ms | 30.0x faster |
  | `read()` of a 690 KB file | 6.30 s | 0.205 s | 30.7x faster |
  | `write()` and `close()` of a 4 KB file | 147.6 ms | 100.7 ms | 1.5x faster |
  | `write()` and `close()` of a 690 KB file | 16.77 s | 9.67 s | 1.7x faster |
  | `rd_str()`, per call | 509.8 µs | 73.7 µs | 6.9x faster |
  | `wr_str()`, per call | 736.3 µs | 450.9 µs | 1.6x faster |
  | `rd_long()`, per call | 43.3 µs | 18.6 µs | 2.3x faster |
  | `wr_long()`, per call | 100.3 µs | 68.9 µs | 1.5x faster |
  | `rd_word()`, per call | 26.1 µs | 18.0 µs | 1.5x faster |
  | `wr_word()`, per call | 53.6 µs | 43.8 µs | 1.2x faster |
  | `rd_byte()`, per call | 13.6 µs | 15.3 µs | 12 % slower |
  | `wr_byte()`, per call | 30.7 µs | 32.3 µs | 5 % slower |

  Median of three runs on a P2 Edge at 320 MHz. The tables in clock ticks are in [DOCs/SPI-PERFORMANCE-ANALYSIS.md](https://github.com/ironsheep/P2-FLASH-FS/blob/main/DOCs/SPI-PERFORMANCE-ANALYSIS.md).
- Every call sets `error()` for the calling cog: SUCCESS, or the reason it failed
- The driver holds one hub lock from the first `mount()` until power-down; each call holds it throughout, and `unmount()` no longer returns it
- A negative count to `read()`, `write()` or `rd_str()` returns E_BAD_FILE_LENGTH and transfers nothing
- E_FILE_WRITING (-5), E_FILE_READING (-6) and E_SHORT_TRANSER (-16) are reserved: no call returns them. A read from a handle not open for reading returns E_FILE_MODE

### Bug Fixes

- Writing until the flash is full returns E_DRIVE_FULL, and no longer risks overwriting the boot image below the filesystem
- When `create_file()` or another `close()` takes the last free block, a `"w"` or `"a"` file over an existing file closes with E_DRIVE_FULL, frees its blocks and keeps the old file
- A `flush()` that finds no free block keeps its data for a later `flush()` or `close()`
- A flash chip that does not finish an erase or program returns E_FLASH_TIMEOUT and unmounts the filesystem; the call no longer hangs
- `"w+"` on an existing file starts an empty file that replaces the old one at `close()` or `flush()`, as documented, instead of editing the old file in place
- `"w"` or `"w+"` on an existing file, closed with no write, deletes the file. `"a"` and `"r+"` closed with no write leave it unchanged
- `"r+"` grows the file when written at or past its end, and `rd_byte()` and `rd_str()` work on `"r+"` handles
- `wr_word()`, `wr_long()` and `wr_str()` report a short write on a full flash
- `unmount()` with files open for writing commits their data, closes every handle, and returns the first close failure
- `mount()` reports E_BAD_BLOCKS_REMOVED when it cancels a bad-CRC or out-of-range block, and removes a file whose chain names a block that cannot exist
- `can_mount()` returns TRUE when already mounted, FALSE with SUCCESS for a duplicate ID alone, and FALSE with E_BAD_BLOCKS_REMOVED for a dead, bad-CRC or out-of-range block
- A second `close()`, or any call on a handle that is not open, returns E_BAD_HANDLE. E_FILE_MODE means an open handle in a mode the call does not serve
- `rd_long()` returns 0 when fewer than four bytes remain. Code that checks `error()` first, as documented, is unaffected
- `create_file()` with a count of 0 or less returns E_BAD_FILE_LENGTH and creates nothing
- An empty name, a NULL pointer or a name of 128 or more characters returns E_BAD_FILENAME from every call that takes a name
- `seek()` to POSX on an empty file gives 0, and `SK_CURRENT_POSN` counts from the handle's true position
- `file_size()`, `file_size_for_handle()` and `seek()` on a trimmed circular file, including a v1.4-format one, count only the bytes the file still holds
- `file_size_for_handle()` on a `"w"` or `"a"` handle gives the size the file will have when committed
- `open_circular()` for read finds a new-format file stored after an old-format one
- `directory()` sets the file size to 0 at the end of the list
- With several cogs sharing the driver, `write()` returns the calling cog's error code, not cog 0's
- `mount()`, `format()` and `can_mount()` return E_NO_HANDLE when `MAX_FILES_OPEN` is below 1, and E_BAD_HANDLE when `HANDLE_BASE` is not 0 or 1, without touching the flash

### Known Issues

- `mount()` assumes no block ID is held by more than two blocks
- Wear-leveling copies a block without first checking its CRC, so a bit error in that block survives the move
- Every call that reaches the flash drives pins 58 to 61 without checking whether another user, such as an SD card, holds them
- Only a 320 MHz system clock is regression-tested; the SPI timing holds up to 350 MHz

## Earlier releases

The releases before v2.1.0, carried over from the driver header:

- v1.2.0 - initial release of flash_fs with full API
- v1.2.1 - revised seek() method parameters - can now seek relative to current position in file
- v1.3.0 - update for flexspin compatibility, seek() returns file position, write() returns bytes written
- v1.3.1 - more update for flexspin compatibility, adjusted seek(), read() and write() add file_size_for_handle()
- v1.4.0 - Adjustments allowing multi-cog support
- v2.0.0 - Add read/modify/write, non-destructive mount check can_mount(), and create_file()
