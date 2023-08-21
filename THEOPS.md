# P2 FLASH Filesystem - Theory of Operations

THis page presents the theory behind our Flash FS a filesystem for the FLASH chip on the P2 Edge Module.

![Project Maintenance][maintenance-shield]

[![License][license-shield]](LICENSE)

## Table of Contents

On this Page:

- [Flash Filesystem Features](#flash-filesystem-features) - key features of this filesystem / design goals
- Initial build - Constants
- Concepts
- File System Block types/format
- Tracking Data
- The Mount Process [M]
- Locating a next block to allocate to a file [L]
- The File Open Process [O]
- The File Close Process [C]
- The File Write Process [W]

Additional pages:

- [SPI FLASH Datasheet](./DOCs/W25Q128JV-210823.pdf) - our FLASH Chip Datasheet
- [Top README](https://github.com/ironsheep/P2-FLASH-FS) - back to the top page of this project

## Flash Filesystem Features

- Wear-leveling write mechanism
- Writes are stuctured to facilitate recovery  of file structure after unplanned power failure
- Can be accessed from all cogs (first cog to call mount() mounts the filesystem for all cogs to use.)

## Initial build - Constants

Key Constants in the file describe:

- **SPI_[CS|CK|DI|DO]** - The signal lines used for the SPI flash chip
- **FIRST_BLOCK** - The starting block to be used within the Flash chip.  By default the value is chosen to allow for the first 512KB to be resorced the boot loaded code for the P2. (Default: $080)
- **LAST_BLOCK** - The address of the last block to be allocated to the filesystem. This effectivly tells us the amount of space which is allocated to this filesystem (Default: $FFF)
- **MAX_FILES_OPEN** - a 4k buffer is allocated to each file we could have open at the same time as another. This is set to 2 so we can at least copy one file to another. (Default: 2)
- **BLOCK_SIZE** - fixed at 4KB, this is the smallest eraseable amount of space within the SPI FLASH chip we use. (Default $1000)

*Most users will not need to adjust these values!*

**NOTE**: *The SPI signal lines are shared with the uSD socket on P2 Edge Modules that have a uSD socket.*

## Concepts

**Block IDs** - block IDs are logical IDs assigned to a block when it is first written, they are not physical block pointers. This allows a block to exist anywhere within the filesystem space without being aware of it's location.  A clock can be relocated (written to a new location and removed from the prior location and the Block's ID will not change.)

**Block Pointers** - Block pointers contain block ID values. Blocks are assigned Block IDs when created. When a block wants to point to another block the ID of the target block (The pointed to block) is the value assigned to the block pointer.

**Block Placement** - to aid in wear leveling all 4k block locations are randomly chosen

## File System Block types/format
Blocks written to our flash filesystem are of the following formats:

| byte offset (hex) | purpose | notes |
| --- | --- | --- |
| **Head/Last block** 
| 000..003 | long {EndPtr[11:0], ThisID[11:0], %vvv11100} | vvv = lifecycle, 00 = head/last
| 004..03F | byte filename[60] | filename
| 040..FFB | byte data[4028] | data
| FFC..FFF | long crc32	 | crc32 of 000..FFB
| **Head/More block** |
| 000..003 | long {NextID[11:0], ThisID[11:0], %vvv11101} | vvv = lifecycle, 01 = head/more
| 004..03F | byte filename[60] | filename
| 040..FFB | byte data[4028] | data
| FFC..FFF | long crc32	 | crc32 of 000..FFB
| **Body/Last block**
| 000..003 | long {EndPtr[11:0], ThisID[11:0], %vvv11110} | vvv = lifecycle, 10 = body/last
| 004..FFB | byte data[4088] | data
| FFC..FFF | long crc32	 | crc32 of 000..FFB
| **Body/More block**
| 000..003 | long {NextID[11:0], ThisID[11:0], %vvv11111} | vvv = lifecycle, 11 = body/more
| 004..FFB | byte data[4088] | data
| FFC..FFF | long crc32	 | crc32 of 000..FFB


### File life-cycle notes

#### Writing to a File

- A filestarts out as a **Head/Last block** and remains so while it is <= 4028 bytes.
- When file gets to 4029 bytes, the 4028+1 byte is written to a **Body/Last block** and the **Head/Last block** is rewritten as a **Head/More block**
- When the file then gets to 4028+4088+1 (the 8117th byte) is written to a new **Body/Last block** and the current **Body/Last block** is rewritten as a **Body/More block**.
- ... and so on ...

#### Appending to an existing File

When appending there are really two cases with the more normal case being the first:

- **Case #1**: In the case of appending to a longer file (a file which is 2 or more blocks) then the append consists of wirting to the **Body/Last block** until we attmpt to write the byte just past then end of theis block. At this time we allocate a new **Body/Last block** to contain this new byte and rewrite the prior **Body/Last block** as a **Body/More block**.

The less frequent case is when we append to a file that contains less than 4028 bytes:

- **Case #2**: In the case of a small file we write into the (**Head/Last block**) until we fill it. Thie growth of this file follows the seqence shown in  "Writing to a File".

## Tracking Data



## The Mount Process [M]

Upon Mount the entire flash space is scanned for well-formed blocks and work is completed if found incomplete. Lastly any badly formed blocks/block chains are freed. In this last case an error code is returned from mount

### [M1] Initial scan
### [M2] Completing work which didn't complete due to power fail
### [M3] Clearing blocks that no longer read correctly

## Locating a next block to allocate to a file [L]

## The File Open Process [O]

## The File Close Process [C]

## The File Write Process [W]


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

Copyright © 2023 Iron Sheep Productions, LLC. All rights reserved.

Licensed under the MIT License.

Follow these links for more information:

### [Copyright](copyright) | [License](LICENSE)

[maintenance-shield]: https://img.shields.io/badge/maintainer-stephen%40ironsheep%2ebiz-blue.svg?style=for-the-badge

[license-shield]: https://camo.githubusercontent.com/bc04f96d911ea5f6e3b00e44fc0731ea74c8e1e9/68747470733a2f2f696d672e736869656c64732e696f2f6769746875622f6c6963656e73652f69616e74726963682f746578742d646976696465722d726f772e7376673f7374796c653d666f722d7468652d6261646765
