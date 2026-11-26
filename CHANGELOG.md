# Changelog

## v2.1.0 (YYYY-MM-DD)

Every call reports its error, the file modes follow ANSI C except where the flash requires otherwise, and reads and writes move runs of bytes.

### Bug Fixes

- `"w"` and `"w+"` on an existing file, closed with no write, delete the file and return SUCCESS. The old file is no longer kept. `"a"` and `"r+"` closed with no write leave the file unchanged.
- `"w+"` on an existing file starts a new empty file and replaces the old one at `close()` or `flush()`. It no longer edits the old file in place, which kept its stale tail records. `exists()` and `file_size()` report the old file until then.
- `"r+"` grows the file when written at or past its end, and `rd_byte()` and `rd_str()` work on `"r+"` handles.
- A full flash returns E_DRIVE_FULL where it could write over the boot area. `close()` and `flush()` report it, and a `flush()` that finds no free block keeps the unwritten data for a later `flush()` or `close()`.
- A `"w"` file over an existing file, or an `"a"` file on an existing file, whose `close()` finds no free block for its last block gives back every block it wrote and leaves the existing file as it was. Before, the blocks it wrote stayed in use until the next `mount()`, which then removed them and returned E_BAD_BLOCKS_REMOVED. Another file's `close()` or a `create_file()` could take the last free block while the file was open.
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

- `read()`, `write()`, `rd_str()` and `wr_str()` move runs of bytes in place of one byte per call. `rd_byte()`, `wr_byte()` and the WORD and LONG calls move a value that lies inside the buffered block directly, and pass a value that reaches the end of the block to the same code as `read()` and `write()`. Figures against v2.0.0, in system clock ticks and µs with the clkfreq stated:

  Measured on a P2 Edge at 320 MHz (1 µs = 320 ticks), built with pnut-ts v1.55.12. Each figure is the median of three runs of each driver.

  | Measurement | v2.0.0 ticks | v2.0.0 µs | v2.1.0 ticks | v2.1.0 µs | Change |
  | --- | ---: | ---: | ---: | ---: | --- |
  | write 4 KB: `write()` calls and `close()` | 47,229,808 | 147,593 | 32,227,072 | 100,709 | 1.5x faster |
  | write 64 KB: `write()` calls and `close()` | 499,277,992 | 1,560,243 | 311,058,872 | 972,058 | 1.6x faster |
  | write 690 KB: `write()` calls and `close()` | 5,367,389,336 | 16,773,091 | 3,092,863,608 | 9,665,198 | 1.7x faster |
  | one whole body block of the 690 KB file, mean `write()` | 30,984,142 | 96,825 | 17,889,506 | 55,904 | 1.7x faster |
  | read 4 KB: `read()` calls | 11,706,848 | 36,583 | 389,696 | 1,217 | 30.0x faster |
  | read 64 KB: `read()` calls | 187,088,024 | 584,650 | 6,115,392 | 19,110 | 30.6x faster |
  | read 690 KB: `read()` calls | 2,016,909,488 | 6,302,842 | 65,665,464 | 205,204 | 30.7x faster |
  | `seek()` from the start to the last byte of the 690 KB file | 1,942,088 | 6,069 | 1,260,464 | 3,938 | 1.5x faster |

  | Call, mean per call | v2.0.0 ticks | v2.0.0 µs | v2.1.0 ticks | v2.1.0 µs | Change |
  | --- | ---: | ---: | ---: | ---: | --- |
  | `wr_byte()`, each byte of a 4 KB file | 9,819 | 30.7 | 10,344 | 32.3 | 5 % slower |
  | `rd_byte()`, each byte of a 4 KB file | 4,349 | 13.6 | 4,882 | 15.3 | 12 % slower |
  | `wr_word()`, each word of a 4 KB file | 17,166 | 53.6 | 14,012 | 43.8 | 1.2x faster |
  | `rd_word()`, each word of a 4 KB file | 8,338 | 26.1 | 5,749 | 18.0 | 1.5x faster |
  | `wr_long()`, each long of a 4 KB file | 32,085 | 100.3 | 22,058 | 68.9 | 1.5x faster |
  | `rd_long()`, each long of a 4 KB file | 13,868 | 43.3 | 5,966 | 18.6 | 2.3x faster |
  | `wr_str()`, 256 strings of 31 characters | 235,609 | 736.3 | 144,304 | 450.9 | 1.6x faster |
  | `rd_str()`, 256 strings of 31 characters, 32-byte buffer | 163,144 | 509.8 | 23,592 | 73.7 | 6.9x faster |

  `rd_byte()` and `wr_byte()` are about 1.5 µs per call slower than in v2.0.0. Each call now re-tests the mount after it takes the lock and releases the lock through the method that unmounts on a device fault; v2.0.0 did neither. `mount()`, `can_mount()` and `format()` take the same time as in v2.0.0, within 2 %.

  After this change, 96.7 % of the time a block read takes is the SPI transfer from the flash, measured at 320 MHz.
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
