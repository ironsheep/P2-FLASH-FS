# P2-FLASH-FS
Flash FS - a filesystem for the FLASH chip on the P2 Edge Module.

![Project Maintenance][maintenance-shield]

[![License][license-shield]](LICENSE)

The following files can be found at the top level of this repository:

| Key Files | Description |
| --- | --- |
| [`flash_fs.spin2`](./flash_fs.spin2) | The complete FLASH driver object
| [`flash_fs.txt`](./flash_fs.txt) | Object Interface Document for the FLASH driver
| [`cgsm_flash_file_demo.zip`](./cgsm_flash_file_demo.zip) | Jon McPhalens latest Interactive Filesystem Demo
| [`flash_fs_demo.spin2`](./flash_fs_demo.spin2) | Chip's original light-weight non-interactive demo

## Table of Contents

On this Page:

- [Flash Filesystem Features](#flash-filesystem-features) - key features of this filesystem / design goals
- [Adding the flash fs to your own project](#adding-the-flash-fs-to-your-own-project)
- [Contributing](#how-to-contribute) - you can contribute to this project

Additional pages:

- [The flash_fs Object I/F Documentation](flash_fs.txt) - the object interface with documentation for each public method
- [SPI FLASH Datasheet](./DOCs/W25Q128JV-210823.pdf) - our FLASH Chip Datasheet
- [FS Theory of Operations](THEOPSv2.md) - a detailed description of key concepts of this filesystem (See [v1.x FS Theory of...](THEOPS.md) for earlier version)
- [Regression Testing Status](./RegresssionTests) - regression test code and output logs - growing as we certify each of the features (900+ tests so far)

## Flash Filesystem Features

Key features of this Flash Filesystem for the P2 Edge Flash chip:

- Wear-leveling write mechanism
- Writes are stuctured to facilitate recovery  of file structure after unplanned power failure
- Block identification is independent of a blocks physical location
- Filenames are 127 characters plus zero terminator
- Seeks supported
- File Append supported
- Read-Modify-Write supported
- Circular file writes supported 
- Supports multi-cog use (first cog to call mount() mounts the filesystem for all cogs to use.)
- **Coming soon** *Directory Support* 

## Features of Note

In addition to standard file operations this filesystem contains a couple features worth noting:

### Feature: Circular files

Circulr files are useful when you want to record the most recent journal entries (or event log entries) in a file.

One writes to circular files by appending to them. At file open, one specifies a maximum limit to the file size in bytes, for example:

```spin2
    status := flash.open_circular(@"filename", "a", 8_192)
    ... many writes ...
    status := flash.close()
```

In this example you see a file being limited to 8k bytes.  This means keep track of the last 8k bytes worth of journal or log entries.  Upon close the journal will be reduced to the requested limit. 

NOTE: Remember to call `flash.flush()` periodically to keep the pending writes small enough so that you don't run out of flash space.

An `open_circular(..., "r", 8_192)` is provided so that one can open the journal file and start reading at the front of the last 8_192 bytes in the file.


### Feature: File Read-Modify-Write

You can now modiify existing files on flash.  Think of a file which contains fixed size records, maybe the state of an array of sensors where each sensor (or group of sensors) is in their own record within the file.

```spin2
    status := flash.open(@"filename", %"r+")  ' alternatively use FILEMODE_READ_EXTENDED for %"r+" 
    ... many  reads and/or replacing writes  ...
    status := flash.close()
```

Open the file with the new %"r+" mode., then seek to the record you wish to replace and write it (replacing the record already there.)  Continue by seeking to locations and writing new records. Of course you can seek to and read the existing records, too.  Lastly close the file as normal.

We also provide an open mode of `flash.open(@"filename", %"w+")` where you first have to write the new records before you can seek to them or replace them with new records.

Lastly we've added a `flash.create_file()` method which you can use to create an initialized file with empty records.  For example:

```spin2
    ' create empty file
    status := flash.create_file(@"filename", $00, 4_096)
    ' now do updates to the file
    status := flash.open(@"filename", %"r+")
    ... many  reads and/or replacing writes  ...
    status := flash.close()
```

In this example we are initilizing a file with 4k bytes of zeros.  You can use any byte value you wish for the fill value.

## Migration from v1.4 to v2.0

There is NO migration needed if you are **not using Circular Files**.

If you are using Circular files and you need to preseve them instead of just creating new ones, then you will first want to copy your exising circular file to a new one. This creates the new file head block supporting circular seeks.

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

## Adding the Flash FS to your own project

This section describes how to quickly get the flash filesystem working in your project.

### Download the latest flash_fs.spin2 file

Every time you wish to start a project using the flash filesystem you will want to download the latest version from the repository [ironsheep/P2-FLASH-FS](https://github.com/ironsheep/P2-FLASH-FS). In the list of files on the top page you will see the file `flash_fs.spin2`. You can download this single file to get the latest or you can navigate to the [releases](https://github.com/ironsheep/P2-FLASH-FS/releases) page where you can download the latest release which includes demo files as well as the filesystem object.

### Include the Flash FS object in your top file

Place the downloaded `flash_fs.spin2` in your project and in your top-level object include the flash object:

```spin2
OBJ { Objects Used by this Object }

    flash  : "flash_fs"	           ' the Flash Filesystem
```

The driver keeps about ~4250 bytes per open file. The space is allocated for two open files by default.  You can override this in your top-level file by changing the include to something like:

```spin2
OBJ { Objects Used by this Object }

    flash  : "flash_fs"	 | MAX_FILES_OPEN = 4       ' the Flash Filesystem
```

In this case we are telling the compiler to allocate room for 4 simultaneously accessable files instead of the default two files.

### Format() or Mount() the flash filesystem

At the start of your application will need to mount() the filesystem.  

```spin2
PRI main() | status

    status := flash.mount()	           ' start up the FLASH filesystem
    if status <> flash.SUCCESS
      '... you know that some blocks were corrupted and freed ...
```

If you know that that the flash chip in your P2 Edge module has never been formatted then you can call format instead of mount. (The format will then do the mount for you.)

```spin2
PRI main()

    flash.format()	           ' start up the FLASH filesystem
```


### Work with files on flash as you would normally

Now that your filesystem is mounted you are free to do normal file operations. The filesystem API is very similar to the ANSI-C file handling API so this all should feel pretty natural to you.

Review the [Flash F/S Object I/F Documentation](flash_fs.txt) then start reading and writing files!

Please Enjoy!
*Stephen*

## How to Contribute

This is a project supporting our P2 Development Community. Please feel free to contribute to this project. You can contribute in the following ways:

- File **Feature Requests** or **Issues** (describing things you are seeing while using our code) at the [Project Issue Tracking Page](https://github.com/ironsheep/P2-FLASH-FS/issues)
- Fork this repo and then add your code to it. Finally, create a Pull Request to contribute your code back to this repository for inclusion with the projects code. See [CONTRIBUTING](CONTRIBUTING.md)

## Credits

Thank you to **Chip Gracey** for the excellent **Flash File System 16MB** written for the P2 which is the core of this fileysystem.

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

[license-shield]: https://camo.githubusercontent.com/bc04f96d911ea5f6e3b00e44fc0731ea74c8e1e9/68747470733a2f2f696d672e736869656c64732e696f2f6769746875622f6c6963656e73652f69616e74726963682f746578742d646976696465722d726f772e7376673f7374796c653d666f722d7468652d6261646765
