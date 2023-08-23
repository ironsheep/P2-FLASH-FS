# P2 FLASH Filesystem - Theory of Operations

THis page presents the theory behind our Flash FS a filesystem for the FLASH chip on the P2 Edge Module.

![Project Maintenance][maintenance-shield]

[![License][license-shield]](LICENSE)

## Table of Contents

On this Page:

- [Flash Filesystem Features](#flash-filesystem-features) - key features of this filesystem / design goals
- [Initial build - Constants](#initial-build---constants)
- [Concepts](#concepts) - and terminology
- [File System Block types/format](#file-system-block-types-and-formats-of-these-blocks)
- [Tracking Data](#tracking-data-state-of-filesystem) - State of Filesystem
- [Tracking Data](#tracking-data-open-files) - Open Files
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
- Block idenitification is independent of physical location

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

**Allocated Block** - A block formatted as one of our block types, it contains a lifeCycle value meaning Active, a block ID, and contains a valid 32-bit CRC of the block.

**Free Block** - A block that is still erased, or a block that contains a lifeCycle value of **Cancelled** or **Inactive**. (Erased blocks appear to have a lifeCycle value of **Inactive**.

**Block Address** - a zero-based address of a block within our filesystem (Default: 0 - 3,967 [$000 - $F7F]).  To this block address we add the offset to the filesystem from the start of the flash chip (Default: $080) to get the physical addreess of the 4kB block within the flash Chip.

**Block IDs** - block IDs are logical IDs assigned to a block when it is first written, they are not physical block addresses or the like. This allows a block to exist anywhere within the filesystem space without being aware of its location or other blocks knowing its location.  A block can be relocated (written to a new location and removed from the prior location) and the Block's ID will not change.  Other blocks referencing a block know the referenced block only by its block ID.

**Block Pointer** - A Block pointer contains a block ID value. Blocks are assigned Block IDs when created. When a block wants to point to another block the ID of the target block (The pointed to block) is the value assigned to the block pointer.

**Block Placement** - to aid in wear leveling all 4k block locations are randomly chosen

**Flash Erase** - the Flash chip supports erasing a block at a time. A block is 4096 bytes. An erase of a block returns all bits of the block to 1 ($FF in all bytes of the block)

**Flash Write** - a flash write only changes 1 bits to 0's. If a bit is 0 it can not be changed until the block containing it is erased at which the time bit becomes 1 once again.

## File System Block Types and Formats of these Blocks

The first long (4-bytes) of each block (addr $000-$003) identifies the block Id, the structure of the remaining bytes in the block, the location of the block within a chain of blocks that comprise a single file, as well as the state of the block.

 
The bits of this first long in the block are interpreted as follows:

| Bit location | xx | xx |
| --- | --- | --- |
| 31..20 | EndPtr -or- NextId | 12-bit field: EndPtr is address of next free byte in block<br>NextID is Block ID of next block in chain 
| 19..8 | ThisID | the Block ID [0-3975] assigned to this block
| 7..5 | LifeCycle | life-cycle state of this block
| 4..2 | Unused | these bits reserved
| 1..0 | Block Type | bit 1x = head/body, bit x1 = last/more <br>which yields: 00 = head/last, 01 = head/more, 10 = body/last, 11 = body/more

The LifeCycle  3-bit field describes the state of the block as inactive, canceled, or active. Active and Canceled LifeCycle values follow rules which are based upon the fact that 1-bits can only transition to 0 on a flash device.  These rules are:

- Active block values follow the single-zero ring counter state sequence: 011..101..110..repeat
- The block with the greater state is the valid block between two blocks with identical IDs
 (Which allows for make-before-break block replacement that can be recovered after unexpected power loss)
- To cancel a block we write a 2nd zero to the life-cycle bits of that block, this returns the block back to an unused state.

This is an overview of the possible values of the three bits:
 
| bit value | meaning | how to recognize
| --- | --- | --- |
| 111 | inactive | no zeroes
| 011/101/110 | **active** | one zero
| 001/010/100/000 | canceled | two or three zeroes

**NOTE1**: A life cycle field transitions from Inactive/formatted (no zero bits) to Active (1 zero bit) to canceled (2 or more 0 bits).

**NOTE2**: When blocks are duplicated with the intent of the newer replacing the older then the active life cycle value transitions from 3 (011) -> 5 (101) -> 6 (110) -> 3 (011) -> ... forever.

This is how we determine age of two blocks with identical Block IDs but the life-cycle bits are different. When we find these we want to finish the transaction by cancelling the older of the two blocks having these matching IDs.

| two life-cycle values compared | age relationship
| --- | --- |
| 011 3 -> 110 6 | new > old (we wrapped from 6 back to 3)
| 101 5 -> 011 3 | new > old
| 110 6 -> 101 5 | new > old


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

#### A File is comprised of blocks

A file made up of these blocks can exist in one of three shapes:

| Constituency | Max size | Notes
| --- | --- | --- |
| Head/Last block | 0 - 4,028 bytes | 1 block file
| Head/More block -> Body/Last block | 0 - 8,116 bytes | 2 block file
| Head/More block -> (1 or more) Body/More block -> Body/Last block | 0 - 16,221,124 bytes | up to a 3,968-block file

**NOTE1**: the largest file would be a 1 x **Head/More block** (4,028 bytes) -> 3,966 x **Body/More block**s (4,088 bytes ea.) -> 1x **Body/Last block** (4,088 bytes) which yeilds a max length of 16,221,124 bytes.

**NOTE2**: Given this block-type composition of our files, our flash chip using this system can contain a **maximum** of 3,968 **files** of 1-4,028 bytes each.


#### Writing to a File

- A filestarts out as a **Head/Last block** and remains so while it is <= 4,028 bytes.
- When file gets to 4,029 bytes, the 4,028+1 byte is written to a **Body/Last block** and the **Head/Last block** is rewritten as a **Head/More block**
- When the file then gets to 4,028+4,088+1 (the 8,117th byte) is written to a new **Body/Last block** and the current **Body/Last block** is rewritten as a **Body/More block**.
- ... and so on ...

#### Appending to an existing File

When appending there are really two cases with the more normal case being the first:

- **Case #1**: In the case of appending to a longer file (a file which is 2 or more blocks) then the append consists of wirting to the **Body/Last block** until we attmpt to write the byte just past then end of theis block. At this time we allocate a new **Body/Last block** to contain this new byte and rewrite the prior **Body/Last block** as a **Body/More block**.

The less frequent case is when we append to a file that contains less than 4,028 bytes:

- **Case #2**: In the case of a small file we write into the (**Head/Last block**) until we fill it. Thie growth of this file follows the seqence shown in  "Writing to a File" (above.)

## Tracking Data (State of Filesystem)

When the filesystem is first mounted the following tables are populated by mount when scanning all the blocks in the space allocated to the filesystem. The tables are:

### Table IDtoBlocks: ID to Block translation

**Physically** this table is a contiguous allocation of WORDs. Its size is calculated so that it can contain a 12-bit variable for each block allocated to the filesystem which is then rounded up to nearest WORD boundary.

```spin2
CON     IdToBlocks_SIZE     = (BLOCKS * 12 + 15) / 16
DAT     IDToBlocks  WORD    0[IdToBlocks_SIZE]   ' ID-to-block translation table
```

**Logically** this table is treated as a contiguous array of 12-bit variables indexed by blockID.
Each 12-bit variable contains the 12-bit block-address to be associated with the index value for that location.  We accomplish this logical behavior by creating a "field pointer" indicating that it points to a 12-bit value within the contiguous allocation of WORDs:

```spin2
    IDToBlock  := ^@IDToBlocks.[11..0]
```

**Access**: To get a blockAddress from this table, we use:

```spin2
	blockAddress := field[IDToBlock][blockID] 
```

This is the way we treat this table as a contiguous allocation of 12-bit variables!

### Table IDValids: ID Valid Flags

This table is initialized to zeros and filling in when mount() is called.

**Physically** this table is a contiguous allocation of BYTEs which consists of 1 byte for every 8 valid block IDs, 1 bit per block ID. Its size is calculated so that it can contain a 1-bit variable for each block allocated to the filesystem which is then rounded up to nearest BYTE boundary.

```spin2
CON     Flags_SIZE		   = (BLOCKS * 1 + 7) / 8
DAT     IDValids  BYTE    0[Flags_SIZE]    'ID-valid flags
```

**Logically** this table is treated as a contiguous array of 1-bit variables indexed by blockID.
Each 1-bit variable contains a [0,1] where 1 means the blockID is in use.  We accomplish this logical behavior by creating a "field pointer" indicating that it points to a 1-bit value within the contiguous allocation of BYTESs:

```spin2
    IDValid    := ^@IDValids.[0]
```

**Access**: To determine if a blockID is valid using this table, we use:

```spin2
	if field[IDValid][blockID]    ' is blockID valid?
```

This is the way we treat this table as a contiguous allocation of 1-bit variables!

### Table: Block States

## Tracking Data (Open Files)

For each open file (handle) we maintain the following information:

- Handle status
- Handle HeadID
- Handle HeadBlock
- Handle HeadCycle
- Handle BlockPtr
- Handle Block Buffer
- Handle Filename


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
