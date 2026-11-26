# P2-FLASH-FS - Regression Test Coverage
Flash FS - a filesystem for the FLASH chip on the P2 Edge Module.

![Project Maintenance][maintenance-shield]

[![License][license-shield]](../LICENSE)

The point of the regression tests is to exercise each method, checking both normal and error/exception cases. Each expectation is what the documented contract says, not what the driver happens to do. This page says which test program checks which method and behavior.

## Table of Contents

On this Page:

- [Test Coverage](#test-coverage) - which programs exercise which method and mode
- [Behaviours the programs check](#behaviours-the-programs-check) - the rules, and the program that holds each
- [How to Contribute](#how-to-contribute) - you can contribute to this project

Additional pages:

- [README](../README.md) - the top page of this project
- [Adding to Your Project](../DEVELOP.md) - download, include, configure, mount, and a complete first program
- [Using the API](../USING.md) - the open modes, how we differ from C, circular files, read-modify-write and multi-cog use
- [Migrating](../MIGRATING.md) - what a v2.0 or v1.4 program may notice in v2.1
- [The flash_fs Object I/F Documentation](../flash_fs.txt) - the object interface with documentation for each public method
- [CHANGELOG](../CHANGELOG.md) - the release history
- [SPI FLASH Datasheet](../DOCs/W25Q128JV-210823.pdf) - our FLASH Chip Datasheet
- [FS Theory of Operations](../THEOPSv2.md) - a detailed description of key concepts of this filesystem
- [v1.x FS Theory of Operations](../THEOPS.md) - the v1 archive, kept for earlier versions
- [Memory Sizing Guide](../DOCs/MEMORY-SIZING-GUIDE.md) - what the driver costs in hub RAM, measured with pnut-ts
- [SPI Performance Analysis](../DOCs/SPI-PERFORMANCE-ANALYSIS.md) - where the time goes in a read, a write and a mount
- [Regression Testing Status](./README.md) - regression test programs and their output logs
- [Contributing](../CONTRIBUTING.md) - how to send a clean pull request

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
| PUB wr\_byte(handle, byte\_value) : result | "w", "a"; across block ends | `RT_write_append_tests`, `RT_typed_boundary_tests`, `RT_full_flash_tests`, `RT_error_paths_tests`, and the helpers in `RT_utilities` |
| PUB wr\_word(), wr\_long(), wr\_str() : result | "w", "a", "r+"; across block ends; a short write on a full flash | `RT_read_write_tests`, `RT_write_append_tests` (typed helpers in `RT_utilities`), `RT_typed_boundary_tests`, `RT_read_write_8cog_tests`, `RT_full_flash_tests`, `RT_error_paths_tests`, `RT_mount_handle_basics_tests` |
| PUB read(handle, p\_buffer, count) : bytes\_read | "r", "r+", "w+"; across block edges; at the end; a negative count | `RT_read_write_block_tests`, `RT_read_write_tests`, `RT_boundary_size_tests`, `RT_seek_edge_tests`, `RT_rmw_extended_tests`, `RT_error_paths_tests` |
| PUB rd\_byte(handle) : value | "r", "r+"; across block ends | `RT_read_write_tests`, `RT_typed_boundary_tests`, `RT_rmw_extended_tests`, `RT_error_paths_tests` |
| PUB rd\_word(), rd\_long() : value | "r", "r+"; across block ends; fewer bytes left than asked | `RT_read_write_tests` (typed helpers in `RT_utilities`), `RT_typed_boundary_tests`, `RT_read_write_8cog_tests`, `RT_rmw_extended_tests`, `RT_error_paths_tests`, `RT_mount_handle_basics_tests` |
| PUB rd\_str(handle, p\_str, buf\_size) : result | buffer edges; truncated and incomplete strings; "r+" | `RT_rd_str_boundary_tests`, `RT_read_write_tests`, `RT_rmw_extended_tests`, `RT_error_paths_tests` |
| PUB directory(p\_block\_id, p\_filename, p\_file\_size) | end of list; a 127-character name | `RT_filename_tests`, `RT_mount_handle_basics_tests`, `RT_seek_edge_tests`, `RT_mount_state_tests`, `RT_error_paths_tests` |
| PUB stats() : used\_blocks, free\_blocks, file\_count | | `RT_rename_delete_tests`, `RT_mount_handle_basics_tests`, `RT_boundary_size_tests`, `RT_filename_tests`, `RT_full_flash_tests`, `RT_error_paths_tests`, `RT_mount_state_tests`, `RT_power_loss_tests` |
| PUB string\_for\_error(error\_code) : p\_interpretation | every code, an unknown code | `RT_error_paths_tests` | the harness uses it for every failure line

The coverage is the call sites in the programs. The test counts in [Regression Tests](README.md) say how many checks each program makes.

## Behaviours the programs check

| Behaviour | Program |
| --- | --- |
| Every open mode on a new and on an existing file: what happens at open, at write, and at close with and without a write; `"w"` and `"w+"` on an existing file closed with no write delete it and return SUCCESS | `RT_rmw_extended_tests` |
| `error()` holds SUCCESS or the call's own code after every call; the four accessors leave a pending code alone | `RT_error_paths_tests` |
| A handle out of range, not open, closed, or closed twice gives E\_BAD\_HANDLE and disturbs no other handle | `RT_error_paths_tests` |
| E\_DRIVE\_FULL from every route: `open()`, `write()` (and from another cog), `open_circular()`, `create_file()`, `rename()`, a close that finds no block, a flush that finds no block, an unmount whose first close fails; a `"w"` or `"a"` file over an existing file that has written blocks when `create_file()` or another handle's close takes the last block gives every block and ID back and leaves the existing file | `RT_full_flash_tests` |
| Byte, WORD and LONG writes and reads whose bytes cross the end of a head block and of a body block, after a seek into such a value, cut short by the end of the file, with "r+" over such a value and growing the file, and with "a" past a full head block | `RT_typed_boundary_tests` |
| A write past the end through "r+" and "w+" grows the file; a seek past the end is refused | `RT_rmw_extended_tests`, `RT_seek_edge_tests` |
| File sizes at the edges of the block layout (head block, head plus one body, 64 KB, 1 MB) | `RT_boundary_size_tests` |
| Names of 1 and 127 characters work; empty, NULL and 128-character names are refused by every call that takes a name | `RT_filename_tests` |
| Block states a power cut can leave, and the flash timeout injected at each step of a commit | `RT_power_loss_tests` |
| Mount state, the lock, and the handle pool across the open modes; `mount()` and `unmount()` from several cogs | `RT_mount_state_tests`, `RT_read_write_8cog_tests` |
| `rd_str()` with a buffer one and two bytes short of the string, exactly as long, 1 or 2 bytes, and a string cut off by the end of the file | `RT_rd_str_boundary_tests` |
| A driver built with `MAX_FILES_OPEN` of 1 works; one built with 0 refuses to mount | `RT_single_handle_smoke_tests` |
| A circular file written by v1.4 reads through its window | `RT_read_circular_compat_tests` |
| Timing of reads, writes, opens, seeks, mount, `can_mount()` and `format()`, in system clock ticks and µs | `RT_performance_baseline` |

## How to Contribute

This is a project supporting our P2 Development Community. Please feel free to contribute to this project. You can contribute in the following ways:

- File **Feature Requests** or **Issues** (describing things you are seeing while using our code) at the [Project Issue Tracking Page](https://github.com/ironsheep/P2-FLASH-FS/issues)
- Fork this repo and then add your code to it. Finally, create a Pull Request to contribute your code back to this repository for inclusion with the projects code. See [CONTRIBUTING](../CONTRIBUTING.md)

---

> If you like my work and/or this has helped you in some way then feel free to help me out for a couple of :coffee:'s or :pizza: slices!
>
> [![coffee](https://www.buymeacoffee.com/assets/img/custom_images/black_img.png)](https://www.buymeacoffee.com/ironsheep) &nbsp;&nbsp; -OR- &nbsp;&nbsp; [![Patreon](../DOCs/images/patreon.png)](https://www.patreon.com/IronSheep?fan_landing=true)[Patreon.com/IronSheep](https://www.patreon.com/IronSheep?fan_landing=true)

---

## Disclaimer and Legal

> *Parallax, Propeller Spin, and the Parallax and Propeller Hat logos* are trademarks of Parallax Inc., dba Parallax Semiconductor
>
> This project is in no way affiliated with, authorized, maintained, sponsored or endorsed by *Parallax Inc., dba Parallax Semiconductor* or any of its affiliates or subsidiaries.

---

## License

Licensed under the MIT License.

Follow these links for more information:

### [Copyright](../copyright) | [License](../LICENSE)

[maintenance-shield]: https://img.shields.io/badge/maintainer-stephen%40ironsheep%2ebiz-blue.svg?style=for-the-badge

[license-shield]: https://img.shields.io/badge/License-MIT-yellow.svg
