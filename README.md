# P2-FLASH-FS
Flash FS - a filesystem for the FLASH chip on the P2 Edge Module.

![Project Maintenance][maintenance-shield]

[![License][license-shield]](LICENSE)

**Latest Changes**

```text
v2.1.0 (2026-11-26)
- Every call reports its error through error(), and the open modes behave as documented
- read(), write() and the typed calls are faster; the timings are tabled in the CHANGELOG
- New: HANDLE_BASE, and the error codes E_BAD_FILENAME and E_FLASH_TIMEOUT
- A flash chip that does not finish an erase or program returns E_FLASH_TIMEOUT instead of hanging
- Upgrading from v2.0? See MIGRATING.md
```

## Table of Contents

On this Page:

- [The Project](#the-project) - what the Flash FS is, and whether it fits your project
- [Flash Filesystem Features](#flash-filesystem-features) - key features of this filesystem / design goals
- [Quick start](#quick-start) - include it, mount it, use it
- [Known limits](#known-limits) - what the driver does not check
- [How to Contribute](#how-to-contribute) - you can contribute to this project

Additional pages:

- [Adding to Your Project](DEVELOP.md) - download, include, configure, mount, and a complete first program
- [Using the API](USING.md) - the open modes, how we differ from C, circular files, read-modify-write and multi-cog use
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

## The Project

Provide a ready-to-use object, easily incorporated into your own code, that gives your Parallax Propeller 2 [P2 or P2X8C4M64P] project a filesystem. The Flash FS manages the 16 MB SPI flash chip (a W25Q128JV) on the Parallax P2 Edge Module and gives you an ANSI-C-like file API: `open()`, `read()`, `write()`, `seek()` and `close()`, with a handle for each open file. The first 512 KB of the flash stays reserved for the boot image.

The following files can be found at the top level of this repository:

| Key Files | Description |
| --- | --- |
| [`flash_fs.spin2`](./flash_fs.spin2) | The complete FLASH driver object
| [`flash_fs.txt`](./flash_fs.txt) | Object Interface Document for the FLASH driver
| [`CHANGELOG.md`](./CHANGELOG.md) | What changed in each release
| [`cgsm_flash_file_demo.zip`](./cgsm_flash_file_demo.zip) | Jon McPhalen's latest Interactive Filesystem Demo
| [`flash_fs_demo.spin2`](./flash_fs_demo.spin2) | Chip's original light-weight non-interactive demo

Will it fit your project?

| Question | Answer |
| --- | --- |
| How big is it? | 3,968 blocks of 4 KB; up to 3,968 files; filenames of 1 to 127 characters; the largest single file is 16,221,052 bytes ([how that is worked out](THEOPSv2.md#a-file-is-comprised-of-blocks)) |
| How much hub RAM? | 32,412 bytes at the default of 2 open files ([Memory Sizing Guide](DOCs/MEMORY-SIZING-GUIDE.md#3-driver-standalone-reading-the-map-file)) |
| Which board? | The Parallax P2 Edge Module; the driver uses pins P58 to P61 |
| Which compilers? | pnut-ts v1.55.12: driver, demos and the full regression suite, run on a P2 Edge. FlexSpin 7.6.1: the driver compiles with no warning or error. Propeller Tool: not tested. |

## Flash Filesystem Features

Key features of this Flash Filesystem for the P2 Edge Flash chip:

- Wear-leveling write mechanism
- Writes are structured to facilitate recovery of file structure after unplanned power failure
- Block identification is independent of a block's physical location
- Filenames are 1 to 127 characters (plus the zero terminator)
- Seeks supported
- File Append supported
- Read-Modify-Write supported, see [Features of Note](USING.md#features-of-note)
- Circular file writes supported, see [Features of Note](USING.md#features-of-note)
- Supports multi-cog use, see [Multi-cog use](USING.md#multi-cog-use)
- Fast bulk transfers: `read()`, `write()`, `rd_str()` and `wr_str()` move runs of bytes, not one byte per call, see [SPI Performance Analysis](DOCs/SPI-PERFORMANCE-ANALYSIS.md)
- Handle numbers count from 0 (the default) or from 1 (`HANDLE_BASE`), see [Configuring the driver](DEVELOP.md#step-3-configuring-the-driver)
- `error()` is kept per cog and holds the reason for the last failed call
- **Coming soon:** directory emulation, `/`-separated paths with a per-cog current directory, as in the [P2 Dual uSD FAT32 and FLASH FS](https://github.com/ironsheep/P2-Dual-uSD-FAT32-n-FLASH-FS) driver

## Quick start

Download `flash_fs.spin2` from the [latest release](https://github.com/ironsheep/P2-FLASH-FS/releases), put it in your project, and include it in your top-level object. You simply include the file with something like:

```spin2
OBJ { Objects Used by this Object }

    flash  : "flash_fs"    ' the Flash Filesystem
```

Then mount the filesystem at the start of your application. On a flash chip that has never been formatted, call `flash.format()` once instead (it mounts for you):

```spin2
PRI main() | status

    status := flash.mount()                 ' start up the FLASH filesystem
```

[Adding to Your Project](DEVELOP.md) has the steps in full, the constants you can override and a complete first program. [Using the API](USING.md) says how each open mode behaves and where we differ from C. Upgrading? See [Migrating](MIGRATING.md).

Please Enjoy!  
*Stephen*

## Known limits

The driver does not check or handle these. They are also listed in the driver's header.

- **Two copies of an ID, at most.** A power loss part-way through moving a block leaves two blocks with one ID, and `mount()` resolves the pair by keeping the newer. It assumes no ID is held by more than two blocks.
- **Moving a block does not check its CRC first.** When the driver moves a block to wear-level the flash, it copies the data and computes a new CRC over the copy. The CRC of the block being moved is not checked, so a bit error in it is copied into a block that then looks good.
- **Pins 58 to 61 are taken on every call.** Every call that reaches the flash drives the flash chip's pins and does not check whether another user of those pins (an SD card, for example) holds them. The [SPI Performance Analysis](DOCs/SPI-PERFORMANCE-ANALYSIS.md#4-p2-edge-hardware-constraints) lists the pins.
- **The driver is tested at a 320 MHz system clock.** Every regression run uses 320 MHz. The SPI timing holds up to 350 MHz.

## How to Contribute

This is a project supporting our P2 Development Community. Please feel free to contribute to this project. You can contribute in the following ways:

- File **Feature Requests** or **Issues** (describing things you are seeing while using our code) at the [Project Issue Tracking Page](https://github.com/ironsheep/P2-FLASH-FS/issues)
- Fork this repo and then add your code to it. Finally, create a Pull Request to contribute your code back to this repository for inclusion with the projects code. See [CONTRIBUTING](CONTRIBUTING.md)

---

> If you like my work and/or this has helped you in some way then feel free to help me out for a couple of :coffee:'s or :pizza: slices!
>
> [![coffee](https://www.buymeacoffee.com/assets/img/custom_images/black_img.png)](https://www.buymeacoffee.com/ironsheep) &nbsp;&nbsp; -OR- &nbsp;&nbsp; [![Patreon](./DOCs/images/patreon.png)](https://www.patreon.com/IronSheep?fan_landing=true)[Patreon.com/IronSheep](https://www.patreon.com/IronSheep?fan_landing=true)

---

## Credits

Thank you to **Chip Gracey** for the excellent **Flash File System 16MB** written for the P2 which is the core of this filesystem.

Thank you to **Jon McPhalen** for helping to specify the customer facing API for this filesystem and for guidance in our future directions for the upcoming dual filesystem driver as well. Jon also contributed his interactive filesystem demo.

Thank you also to members of the [forum thread - "On-Board Flash File System"](https://forums.parallax.com/discussion/175470/on-board-flash-file-system#latest) for also contributing ideas and guidance for implementation of this driver.

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
