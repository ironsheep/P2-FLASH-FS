# P2-FLASH-FS - Adding the Flash FS to your own project
Add a filesystem for the FLASH chip on the P2 Edge Module to your own project!

![Project Maintenance][maintenance-shield]

[![License][license-shield]](LICENSE)

Follow these steps to add the Flash FS to your project:

## Table of Contents

On this Page:

- [Step 1: Download the latest flash_fs.spin2 file](#step-1-download-the-latest-flash_fsspin2-file) - one file is all you need
- [Step 2: Include the Flash FS object in your top file](#step-2-include-the-flash-fs-object-in-your-top-file) - the OBJ line
- [Step 3: Configuring the driver](#step-3-configuring-the-driver) - MAX_FILES_OPEN, HANDLE_BASE, the limits, and what a handle costs
- [Step 4: Format() or Mount() the flash filesystem](#step-4-format-or-mount-the-flash-filesystem) - get the filesystem ready
- [Step 5: A complete first program](#step-5-a-complete-first-program) - mount, write a file, read it back, check errors
- [Step 6: Work with files on flash as you would normally](#step-6-work-with-files-on-flash-as-you-would-normally) - where to go next
- [How to Contribute](#how-to-contribute) - you can contribute to this project

Additional pages:

- [README](README.md) - the top page of this project
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

## Step 1: Download the latest flash_fs.spin2 file

Every time you wish to start a project using the flash filesystem you will want to download the latest version from the repository [ironsheep/P2-FLASH-FS](https://github.com/ironsheep/P2-FLASH-FS). In the list of files on the top page you will see the file `flash_fs.spin2`. You can download this single file to get the latest or you can navigate to the [releases](https://github.com/ironsheep/P2-FLASH-FS/releases) page where you can download the latest release which includes demo files as well as the filesystem object.

## Step 2: Include the Flash FS object in your top file

Place the downloaded `flash_fs.spin2` in your project and in your top-level object include the flash object. You simply include the file with something like:

```spin2
OBJ { Objects Used by this Object }

    flash  : "flash_fs"    ' the Flash Filesystem
```

The space for two open files is allocated by default. You can override this in your top-level file by changing the include to something like:

```spin2
OBJ { Objects Used by this Object }

    flash  : "flash_fs" | MAX_FILES_OPEN = 4    ' the Flash Filesystem
```

In this case we are telling the compiler to allocate room for 4 simultaneously accessible files instead of the default two files. The next step lists the other constants you can override.

## Step 3: Configuring the driver

The constants below are overridden where you include the driver, on the `OBJ` line. The compiler checks none of the values: `mount()`, `format()` and `can_mount()` check `MAX_FILES_OPEN` and `HANDLE_BASE` when they run, before they take the lock or touch the flash.

```spin2
OBJ { Objects Used by this Object }

    flash  : "flash_fs" | MAX_FILES_OPEN = 4, HANDLE_BASE = 1    ' the Flash Filesystem
```

| Constant | Default | Valid values | What it sets |
| --- | --- | --- | --- |
| `MAX_FILES_OPEN` | 2 | 1 or more | The number of files that can be open at one time, which is the number of handles. Each handle takes hub RAM, see [what a handle costs](#what-a-handle-costs). Below 1, `mount()`, `format()` and `can_mount()` return E_NO_HANDLE |
| `HANDLE_BASE` | 0 | 0 or 1 | The value of the first handle `open()` returns. The handles are `HANDLE_BASE` to `HANDLE_BASE + MAX_FILES_OPEN - 1`, and every method that takes a handle takes one of these. Any other value makes `mount()`, `format()` and `can_mount()` return E_BAD_HANDLE |
| `FIRST_BLOCK` | `$080` | | The first 4 KB block of the flash the filesystem uses. The default leaves the first 512 KB for the boot image |
| `LAST_BLOCK` | `$FFF` | | The last block it uses. `LAST_BLOCK - FIRST_BLOCK + 1` can be no more than 4,095 blocks: a block ID is a 12-bit field, and the driver keeps one more value for its own use |

These are not constants to override:

- A file name is at most 127 characters (a zero terminator follows it).
- The driver serves at most 8 cogs at once.

### What a handle costs

Each handle holds a block buffer, a filename buffer and a little state, in hub RAM. The [Memory Sizing Guide](DOCs/MEMORY-SIZING-GUIDE.md#5-impact-of-max_files_open) gives the figure per handle and shows how to measure it for your own build.

### The handle convention

`open()` and `open_circular()` return a handle, or a negative error code in its place. With the default `HANDLE_BASE` of 0, handle 0 is a good handle, so test a result with `< 0` and not `== 0`. A program that counts handles from 1, a FemtoBasic program for example, sets `HANDLE_BASE = 1`. A handle outside the range, or one that is in range and not open, returns E_BAD_HANDLE from every method that takes a handle.

## Step 4: Format() or Mount() the flash filesystem

At the start of your application you will need to mount() the filesystem.

```spin2
PRI main() | status

    status := flash.mount()                 ' start up the FLASH filesystem
    if status <> flash.SUCCESS
      '... you know that some blocks were corrupted and freed ...
```

`mount()` returns E_BAD_BLOCKS_REMOVED when it cancelled blocks that were damaged or that no file reached; the filesystem is mounted and usable either way. Other codes (E_NO_LOCK_AVAIL, E_FLASH_TIMEOUT) mean it is not mounted.

If you know that the flash chip in your P2 Edge Module has never been formatted then you can call format instead of mount. (The format will then do the mount for you.)

```spin2
PRI main()

    flash.format()                          ' erase the filesystem area, then mount it
```

**NOTE:** *format() erases every file in the filesystem area. Use it for the first run on a new flash, or when you want everything gone.*

## Step 5: A complete first program

This program mounts the filesystem (or formats it on a flash that has never been formatted), writes a file, reads it back and checks `error()` after each step. Every call in it is documented in [flash_fs.txt](flash_fs.txt).

```spin2
CON { timing }

    _CLKFREQ = 320_000_000                      ' the system clock the driver is tested at

CON { first run }

    NEVER_FORMATTED = TRUE                      ' TRUE only for the first run on a never-formatted flash

OBJ { Objects Used by this Object }

    flash   : "flash_fs"                        ' the Flash Filesystem

DAT

    message     BYTE    "Hello from the flash filesystem", 0

PUB main() | status, handle, count, BYTE readBuf[64]

    ' --- mount, or format a flash that has never been formatted
    if NEVER_FORMATTED
        status := flash.format()                ' erases the filesystem area, then mounts it
    else
        status := flash.mount()
    ifnot flash.mounted()                       ' E_BAD_BLOCKS_REMOVED still leaves it mounted
        showError(@"mount()", status)
        return

    ' --- write a file
    handle := flash.open(@"hello.txt", "w")
    if handle < 0                               ' a negative handle is an error code
        showError(@"open() for write", handle)
        return
    count := flash.write(handle, @message, strsize(@message))
    status := flash.error()                     ' SUCCESS unless the write stopped short
    if status <> flash.SUCCESS
        showError(@"write()", status)
    status := flash.close(handle)               ' the file reaches the flash at close()
    if status <> flash.SUCCESS
        showError(@"close() after write", status)
        return

    ' --- read it back
    handle := flash.open(@"hello.txt", "r")
    if handle < 0
        showError(@"open() for read", handle)
        return
    count := flash.read(handle, @readBuf, strsize(@message))
    status := flash.error()                     ' E_END_OF_FILE would mean fewer bytes than asked
    if status <> flash.SUCCESS
        showError(@"read()", status)
    flash.close(handle)
    if status == flash.SUCCESS
        readBuf[count] := 0                     ' make the bytes a zstring
        debug("Read back: ", zstr_(@readBuf))

    ' --- and do your app stuff from here on ...

PRI showError(pCaller, errorCode)

    debug("Error in ", zstr_(pCaller), ": ", zstr_(flash.string_for_error(errorCode)))
```

Set `NEVER_FORMATTED` to FALSE after the first run, so that the next run keeps your files.

## Step 6: Work with files on flash as you would normally

Now that your filesystem is mounted you are free to do normal file operations. The filesystem API is very similar to the ANSI-C file handling API so this all should feel pretty natural to you. Where it differs, [Differences from ANSI C](USING.md#differences-from-ansi-c) says how and why. The driver does not check some things, such as another user of the flash pins, and the README lists them under [Known limits](README.md#known-limits).

Review the [Flash FS Object I/F Documentation](flash_fs.txt) then start reading and writing files!

That's all there is to it! Please Enjoy!

*Stephen*

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
