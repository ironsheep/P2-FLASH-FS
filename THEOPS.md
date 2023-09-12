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
  - [Writing to a file](#writing-to-a-file)
  - [Appending to an existing File](#appending-to-an-existing-file)
  - [Seeking within an existing File](#seeking-within-an-existing-file)
  - [Treating a file as a circular buffer](#treating-a-file-as-a-circular-buffer)
- [Tracking Data](#tracking-data-state-of-filesystem) - State of Filesystem
- [Tracking Data](#tracking-data-open-files) - Open Files
- [The Format Process [F]](#the-format-process-f)
- [The Mount Process [M]](#the-mount-process-m)
- [Locating a next block to allocate to a file [L]](#locating-a-next-block-to-allocate-to-a-file-l)
- *Want to see somthing else explained in this document?  Please let me know.*


Additional pages:

- [SPI FLASH Datasheet](./DOCs/W25Q128JV-210823.pdf) - our FLASH Chip Datasheet
- [Top README](https://github.com/ironsheep/P2-FLASH-FS) - back to the top page of this project

## Flash Filesystem Features

- Wear-leveling write mechanism
- Writes are stuctured to facilitate recovery  of file structure after unplanned power failure
- Can be accessed from all cogs (first cog to call mount() mounts the filesystem for all cogs to use.)
- Block identification is independent of a blocks physical location
- Filenames are 127 characters plus zero terminator
- Seeks supported
- File Append supported
- Read-Modify-Write supported
- Circular file writes supported (simulation)
- Directory features coming soon (simulation)


## Initial build - Constants

Key Constants in the file describe:

- **SPI_[CS|CK|DI|DO]** - The signal lines used for the SPI flash chip
- **FIRST_BLOCK** - The starting block to be used within the Flash chip.  By default the value is chosen to allow for the first 512KB to be resorced the boot loaded code for the P2. (Default: $080)
- **LAST_BLOCK** - The address of the last block to be allocated to the filesystem. This effectivly tells us the amount of space which is allocated to this filesystem (Default: $FFF)
- **MAX\_FILES_OPEN** - a 4k buffer is allocated to each file we could have open at the same time as another. This is set to 2 so we can at least copy one file to another. (Default: 2)
- **BLOCK_SIZE** - fixed at 4KB, this is the smallest eraseable amount of space within the SPI FLASH chip we use. (Default $1000)

*Most users will not need to adjust these values!*

**NOTE**: *The SPI signal lines are shared with the uSD socket on P2 Edge Modules that have a uSD socket.*

## Concepts

**Allocated Block** - A block formatted as one of our block types, it contains a lifeCycle value meaning Active, a block ID, and contains a valid 32-bit CRC of the block.

**Free Block** - A block that is still erased, or a block that contains a lifeCycle value of **Cancelled** or **Inactive**. (Erased blocks appear to have a lifeCycle value of **Inactive**.

**Block Address** - a zero-based address of a block within our filesystem (Default: 0 - 3,967 [$000 - $F7F]).  We add to this block address the offset to the filesystem from the start of the flash chip (Default: $080) to get the physical address of the 4kB block within the flash Chip.

**Block IDs** - block IDs are logical IDs assigned to a block when it is first written, they are not physical block addresses or the like. This allows a block to exist anywhere within the filesystem space without being aware of its location or other blocks knowing its location.  A block can be relocated (written to a new location and removed from the prior location) and the Block's ID will not change.  Other blocks referencing a block know the referenced block only by its block ID.

**Block Pointer** - A Block pointer contains a block ID value. Blocks are assigned Block IDs when created. When a block wants to point to another block the ID of the target block (The pointed to block) is the value assigned to the block pointer.

**Block Placement** - to aid in wear leveling, all 4k block locations are randomly chosen

**Cancel a block** - Blocks in the file system have a life-cycle indication. When a block is to be freed/excluded from being part of a file. Then the block's life-cycle is written as %000 (3 bits of zero) This marks the block as available for use.

**Commit chain** - a set of file writes that upon close will become a new file, replace an existing file, or will replace the tail of an existing file.

**Flash Erase** - the Flash chip supports erasing a block at a time. A block is 4096 bytes. An erase of a block returns all bits of the block to 1 ($FF in all bytes of the block)

**Flash Write** - a flash write only changes 1 bits to 0's. If a bit is 0 it can not be changed until the block containing it is erased at which the time bit becomes 1 once again.

**Life Cycle** - a 3-bit field within each of our blocks that indicates precedence of blocks having the same **block ID**.

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
| 004..007 | long {Filename crc32} | crc32 of filename + terminator
| 008..087 | byte filename[127+1] | filename + terminator
| 088..FFB | byte data[3956] | data
| FFC..FFF | long crc32	 | crc32 of 000..FFB
| **Head/More block** |
| 000..003 | long {NextID[11:0], ThisID[11:0], %vvv11101} | vvv = lifecycle, 01 = head/more
| 004..007 | long {Filename crc32} | crc32 of filename + terminator
| 008..087 | byte filename[127+1] | filename + terminator
| 088..FFB | byte data[3956] | data
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

A file is a one-way linked list. From the study of the block structures above, we see that the file contains control structures and data. The last bock of the file aways contains the End-Pointer which is the address of the next byte to be written or the value of $FFC which points to the CRC which means there is no more room to write in this block. In this condition (end pointer is $FFC) a next write to this file will first allocate a new block adding more space in which to write. The End pointer in this new last block is set to the first byte of data space in the new block. The former last block is set to point to the new last block and its type is set to body/more instead of body/last.

The file's control data also contains logical next pointers in each block except the last block. These next pointers contain the block ID of next block that is part of this file. WE use block IDs instead of block addreses so the blocks containing the ID can be replaced with another block having the same ID when the file content changes but the block pointing to this ID don't have to change. 

A file made up of these blocks can exist in one of three shapes:

| Constituency | Max size | Notes
| --- | --- | --- |
| Head/Last block | 0 - 3,956 bytes | 1 block file
| Head/More block -> Body/Last block | 0 - 8,044 bytes | 2 block file
| Head/More block -> (1 or more) Body/More block -> Body/Last block | 0 - 16,221,052 bytes | up to a 3,968-block file

**NOTE1**: the largest file would be a 1 x **Head/More block** (3,956 bytes) -> 3,966 x **Body/More block**s (4,088 bytes ea.) -> 1x **Body/Last block** (4,088 bytes) which yields a max length of 16,221,052 bytes.

**NOTE2**: Given this block-type composition of our files, our flash chip using this system can contain a **maximum** of 3,968 **files** ea. 1 block, 3,956 bytes each.

#### File open(filename, mode) Supported Modes

| Open Mode | supports seek() | description |
| --- | --- | ---|
| <pre>read ["r", "R"]</pre>  | YES | Read from an **existing file**,<BR>Supports direct access via seek() |
| <pre>write ["w", "W"]</pre>   | no | Write to a **new file**, creating it (or write to an **existing file**, replacing it))<br>use `if exists(@"filename") ...` to avoid overwriting an <BR>existing file |
| <pre>append ["a", "A"]</pre> | no | Write to an **existing file**, extending the existing file. If the file didn't exist then this becomes a write ["w", "W"]  |


#### Writing to a File

- A filestarts out as a **Head/Last block** and remains so while it is <= 3,956 bytes.
- When file gets to 3,957 bytes, the 3,956+1 byte is written to a **Body/Last block** and the **Head/Last block** is rewritten as a **Head/More block**
- When the file then gets to 3,956+4,088+1 (the 8,045th byte) is written to a new **Body/Last block** and the current **Body/Last block** is rewritten as a **Body/More block**.
- ... and so on ...

#### Appending to an existing File

When appending there are really two cases with the more normal case being the first:

- **Case #1**: In the case of appending to a longer file (a file which is 2 or more blocks) then the append consists of wirting to the **Body/Last block** until we attmpt to write the byte just past then end of theis block. At this time we allocate a new **Body/Last block** to contain this new byte and rewrite the prior **Body/Last block** as a **Body/More block**.

The less frequent case is when we append to a file that contains less than 3,956 bytes:

- **Case #2**: In the case of a small file we write into the (**Head/Last block**) until we fill it. Thie growth of this file follows the seqence shown in  "Writing to a File" (above.)

#### BEHAVIOR: Writing, Replacing, Appending

When a file is opened for sequential writing all the writes are accumulated into what we call a "commit chain". As a commit chain block fills it is written to the filesystem. Upon close the last block is written to the filesystem. Lastly, the commit chain head block is activated. If there was a prior file (we are overwriting or appending) then the commit head block will supercede the prior files block and the prior block(s) will be deleted. If the power fails just before the head  is activated, the block will be discovered (block of same ID but with newer lifecycle) at mount and the older block will be canceled during the mount.

##### Actions unique to open() mode

When we **open(filename, "W")** and **there is no prior file** (Write) then we are creating a new file. In this case there is no prior block to be replaced at close.


When we **open(filename, "W")** and a **prior file DOES exist** (Replace) then we are also creating a new file but upon close we are replacing the prior file, deleting all the blocks associated with the prior file.

When we **open(filename, "A")** and **there is no prior file** (Write) then we are creating a new file. In this case there is no prior block to be replaced at close.

When we **open(filename, "A")** and a **prior file DOES exist** (Append) then we are opening the file, seeking to the end and then writing bytes beyond the end of the original file. Upon close the commit head block will be activated to replace the tail block of the original file.


#### BEHAVIOR: Seeking within an existing File opened for Read

Seeking within an existing file is supported without any control structures being recorded/or updated within the file itself. A seek pointer is maintained for the open file handle. When a seek is requested the location is stored in the handle state data and the block underlying that location is loaded into the handle's buffer. When a read follows the seek the seek pointer is updated with the length of the data read.

#### BEHAVIOR: Treating a file as a Circular Buffer

Maintaining an existing file in a circular fashion is supported without any control structures being recorded/or updated within the file itself.  We are implementing this very simply, two new open methods provide the functionality. When **opening for append** or **opening for read** you will **specify the max length of the file** (logically, when you want it to wrap.)  We accomplish the wrap by always appending to the end of the file and removing the head block keeping the file at your desired fixed length. Let's look at this in slightly more detail.

##### File open_circular(filename, mode, max\_file\_length) supported Modes

| Open_circular() Mode | supports seek() | description |
| --- | --- | ---|
| read ["r", "R"] | YES | Read from an **existing file**, first byte read is exactly max\_file\_length from the end of the file (Allocated space will be max\_file\_length rounded up to end of block) Or it will be from first byte if file has not yet grown to max\_file\_length. |
| append ["a", "A"]  | no | Write to an **existing file**, extending the existing file. If the file didn't exist it will be created |

Under the covers this circular behavior affect reads and writes. When **opened for read as circular** the first data returned will be from the front of the file unless the file has reached the max size. If it has then the first data returned will instead be the data at the (file length - max size) offet (The front of your circular buffer.)

When the file is **opened for write as circular** after the write, if a new tail block is added to the file after the file has reached the desired size then the head block will removed and the next body block will be made into the new head block. In net, we've added 4088 bytes to the end of the file and we've removed 4088 bytes from the front of the file.


## Tracking Data (State of Filesystem)

When the filesystem is first mounted the following 3 tables are zeroed and then populated by mount() as it scanns all the blocks in the space allocated to the filesystem. The tables are:

### Table IDtoBlocks: ID to Block translation

This table is initialized to zeros and filled-in when mount() is called. This table is indexed by blockID and returns a blockAddress (The block containing that ID is found at filesystem location blockAddress.)

**Physically** this table is a contiguous allocation of WORDs. Its size is calculated so that it can contain a 12-bit variable for each block allocated to the filesystem which is then rounded up to nearest WORD boundary.

```spin2
CON     IdToBlocks_SIZE     = (BLOCKS * 12 + 15) / 16
DAT     IDToBlocks  WORD    0[IdToBlocks_SIZE]  ' ID-to-block translation table
        IDToBlock   LONG    0                   '(field pointer)
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

This table is initialized to zeros and filled-in when mount() is called. This table is indexed by blockID and returns a [0,1] where 1 means the blockID is in use.

**Physically** this table is a contiguous allocation of BYTEs which consists of 1 byte for every 8 valid block IDs, 1 bit per block ID. Its size is calculated so that it can contain a 1-bit variable for each block allocated to the filesystem which is then rounded up to nearest BYTE boundary.

```spin2
CON     Flags_SIZE		   = (BLOCKS * 1 + 7) / 8
DAT     IDValids  BYTE    0[Flags_SIZE]    'ID-valid flags
        IDValid   LONG    0                '(field pointer)
```

**Logically** this table is treated as a contiguous array of 1-bit variables indexed by blockID.
Each 1-bit variable contains a [0,1] where 1 means the blockID is in use.  We accomplish this logical behavior by creating a "field pointer" indicating that it points to a 1-bit value within the contiguous allocation of BYTEs:

```spin2
    IDValid    := ^@IDValids.[0]
```

**Access**: To determine if a blockID is valid using this table, we use:

```spin2
	if field[IDValid][blockID]    ' is blockID valid?
```

This is the way we treat this table as a contiguous allocation of 1-bit variables!

### Table BlockStates: Block States

This table is initialized to zeros and filled-in when mount() is called.  This table is indexed by blockAddress (offset into the filesystem) and returns a blockState enum value [sFREE, sTEMP, sHEAD, sBODY].

**Physically** this table is a contiguous allocation of BYTEs which consists of 1 byte for every 4 valid block address, 2 bits per block address. Its size is calculated so that it can contain a 2-bit variable for each block allocated to the filesystem which is then rounded up to nearest BYTE boundary.

```spin2
CON     States_SIZE 	= (BLOCKS * 2 + 7) / 8
DAT     BlockStates BYTE    0[States_SIZE]   'block states
        BlockState 	LONG    0                '(field pointer)
```

**Logically** this table is treated as a contiguous array of 2-bit variables indexed by blockAddress (**NOTE**: this is NOT blockID!).
Each 2-bit variable contains a a block state enum value [sFREE, sTEMP, sHEAD, sBODY].  
We accomplish this logical behavior by creating a "field pointer" indicating that it points to a 2-bit value within the contiguous allocation of BYTEs:

```spin2
    BlockState := ^@BlockStates.[1..0]
```

**Access**: To determine the state of a block at blockAddress using this table, we use:

```spin2
	blockState := field[BlockState][blockAddress] 
```

This is the way we treat this table as a contiguous allocation of 2-bit variables!

## Tracking Data (Open Files)

For each open file (handle) teh driver maintains the following information:

| Name |Allocation | Purpose | Notes
| --- | --- | --- | --- |
| | **File State tracking**
| hStatus | BYTE    0[MAX\_FILES_OPEN] | handle: status [H\_READ, H\_WRITE, H\_REPLACE, 0 not in use]| 1 byte
| hHeadBlockAddr | WORD    0[MAX\_FILES_OPEN] | handle: first block_address of file chain | 2 bytes
| hEndPtr | WORD    0[MAX\_FILES_OPEN] | handle: pointer to next write byte in block (or $FFC if block full) | 2 bytes
| hFilename | BYTE    0[MAX\_FILES_OPEN * FILENAME\_SIZE] | handle: 127+1 byte buffer for filename | 128 bytes
| hBlockBuff | BYTE    0[MAX\_FILES_OPEN * BLOCK\_SIZE] | handle: 4KB buffer for file data | <pre>4096 bytes</pre>
| | **Commit-chain tracking**
| hChainBlockID | WORD    0[MAX\_FILES_OPEN] | handle: first blockID of commit chain | 2 bytes
| hChainBlockAddr | WORD    0[MAX\_FILES_OPEN] | handle: first block_address of commit chain | 2 bytes
| hChainLifeCycle | BYTE    0[MAX\_FILES_OPEN] | handle: first block lifecycle (cycle value for replacement first block of commit chain) | 1 byte
| | **Special Mode tracking**<br>**(Seeking, Circular files)**
| hSeekPtr | WORD    NOT\_ENABLED[MAX\_FILES_OPEN] | handle: seek address within active block | 2 bytes
| hCircularLength | WORD    NOT\_ENABLED[MAX\_FILES_OPEN] | handle: circular buffer length in max blocks | 2 bytes
| | | | **4,238 bytes / handle**


## The Format Process [F]

Formatting the Flash is a simple process. The first byte of every block allocated to the flash fileystem is read and if the lifecycle bits indicate the block is active [%011, %101, or %011] then the block is "canceled." That is the lifecyle bits are set to %000 and the byte is written to flash. Once this is complete all blocks will be seen as not in use when the mount occurs.

## The Mount Process [M]

Upon Mount the entire flash space is scanned for well-formed blocks and work is completed if found incomplete. All files are located. Lastly any badly formed blocks/block chains are freed. In this last case an error code is returned from mount.  Here's a bit more detail:

### [M1] Initial scan

The first step in the mount process is to locate all valid active blocks (active lifecycle and valid 32-bit block CRC) and check for any duplicate block IDs. If a duplicate is found then the valid block with the higher priority is kept while the block with the lower priority is "canceled.".  In actuality, there should only ever be one occurance of this. A 2nd case should never be found. This one occurance would be due to a power failure occurring after the block with the higher priority was written but before the block with the lower priority could be canceled.
 
This step in the mount process effectively finishes the work that didn't complete due to a power failure.

### [M2] Locating complete files and canceling incomplete

This next step uses the product of the first step. The first step left indications of which blocks are valid within the entire space allocated to the flash filesystem.  This step then iterates over the known good blocks identifying which are file head blocks [HEAD/last block or HEAD/more block] and then locating all remaining blocks in the file chain.

The end product of this seach is that all file locations are now known in addition to which blocks belong to files.  We also know if any blocks are somehow active but no longer belong to any files.

### [M3] Clearing blocks that no longer read correctly

The final pass then clears these somehow damaged blocks by canceling each of them effectively marking each of them as free/not in use.  This "clearing" is not a normal case. It only happens when the flash memory has somehow changed state (or aged.). In the case of blocks being found during the mount effort and then canceled an error code **E\_BAD\_BLOCKS_REMOVED** is returned from the mount call.  This is to allow and application to be able to detect if files are somehow being lost to the aging effects of the flash chip.

## Locating a next block to allocate to a file [L]

Our wear leveling is accomplished by two mechanisms. The first is by how we choose a block to be allocated. We randomly pick a block from within the entire flash filesystem space. The 2nd mechanism then ensures the leveling. Once the new location is randomly determined then if the block is already in use we relocate the contents of that block and continue to place our new content in this location.

## This is my first ...

This is my first version of this Theory of Operations Document. If I've not covered something here that you would like to see please let me know by filing issue, contacting me directly or by posting your request in our P2 Forums.

Please enjoy!

 *Stephen*


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
