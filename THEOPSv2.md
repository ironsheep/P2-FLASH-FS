# P2 FLASH Filesystem - Theory of Operations - v2.x.x+

This page presents the theory behind our Flash FS a filesystem for the FLASH chip on the P2 Edge Module.  

This page applies to v2 and above. For earlier versions see [Theory of Operation v1.x.x](./THEOPS.md)

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
  - [Replacing records within a File](#replacing-records-within-a-file)
  - [Writing, Overwriting, Appending](#behavior-writing-overwriting-appending)
  - [Seeking within a File](#behavior-seeking-within-a-file-opened-for-read-readmodify-or-writemodify)
  - [Treating a file as a circular buffer](#behavior-treating-a-file-as-a-circular-buffer)
  - [Treating a file as Modifiable (replacing records within a file)](#behavior-treating-a-file-as-modifiable-replacing-records-within-a-file)
- [Tracking Data](#tracking-data-state-of-filesystem) - State of Filesystem
- [Tracking Data](#tracking-data-open-files) - Open Files
- [The Format Process [F]](#the-format-process-f)
- [The Mount Process [M]](#the-mount-process-m)
- [Locating a next block to allocate to a file [L]](#locating-a-next-block-to-allocate-to-a-file-l)
- [Locking: how cogs share the filesystem [K]](#locking-how-cogs-share-the-filesystem-k)
- [Device faults [D]](#device-faults-d)
- *Want to see something else explained in this document?  Please let me know.*


Additional pages:

- [SPI FLASH Datasheet](./DOCs/W25Q128JV-210823.pdf) - our FLASH Chip Datasheet
- [Top README](https://github.com/ironsheep/P2-FLASH-FS) - back to the top page of this project

## Flash Filesystem Features

- Wear-leveling write mechanism
- Writes are stuctured to facilitate recovery  of file structure after unplanned power failure
- Can be accessed from all cogs (the first mount() of the run creates the lock all cogs use; see [Locking](#locking-how-cogs-share-the-filesystem-k))
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
- **MAX\_FILES_OPEN** - a 4k buffer is allocated to each file we could have open at the same time as another. This is set to 2 so we can at least copy one file to another. Each handle takes 4,264 bytes of hub RAM (4,096 for the block buffer, 128 for the filename, 40 of state). Valid values are 1 or more; below 1, mount() returns E_NO_HANDLE. (Default: 2)
- **HANDLE_BASE** - the value of the first handle open() returns, 0 or 1. Any other value makes mount() return E_BAD_HANDLE. (Default: 0)
- **BLOCK_SIZE** - fixed at 4KB, this is the smallest eraseable amount of space within the SPI FLASH chip we use. (Default $1000)

*Most users will not need to adjust these values!*  The README's "Configuring the driver" section shows how to override them.

**NOTE**: *The SPI signal lines are shared with the uSD socket on P2 Edge Modules that have a uSD socket.*

## Concepts

**Allocated Block** - A block formatted as one of our block types, it contains a lifeCycle value meaning Active, a block ID, and contains a valid 32-bit CRC of the block.

**Free Block** - A block that is still erased, or a block that contains a lifeCycle value of **Cancelled** or **Inactive**. (Erased blocks appear to have a lifeCycle value of **Inactive**.

**Block Address** - a zero-based address of a block within our filesystem (Default: 0 - 3,967 [$000 - $F7F]).  We add to this block address the offset to the filesystem from the start of the flash chip (Default: $080) to get the physical address of the 4kB block within the flash Chip.

**Block IDs** - block IDs are logical IDs assigned to a block when it is first written, they are not physical block addresses or the like. This allows a block to exist anywhere within the filesystem space without being aware of its location or other blocks knowing its location.  A block can be relocated (written to a new location and removed from the prior location) and the Block's ID will not change.  Other blocks referencing a block know the referenced block only by its block ID.

**Block Pointer** - A Block pointer contains a block ID value. Blocks are assigned Block IDs when created. When a block wants to point to another block the ID of the target block (The pointed to block) is the value assigned to the block pointer.

**Block Placement** - to aid in wear leveling, all 4k block locations are randomly chosen

**Cancel a block** - Blocks in the file system have a life-cycle indication. When a block is to be freed/excluded from being part of a file. Then the block's life-cycle is written as %000 (3 bits of zero) This marks the block as available for use.

**Activate a block** - a block is written to the flash with its life-cycle bits still erased (%111, inactive), and its CRC is computed as if the life-cycle held the value it will have once active. Activating the block is then one more write of its first byte, which clears one life-cycle bit. A block is therefore either not on the flash at all (inactive: free), or whole and active. A power loss between the two writes leaves an inactive block that mount() treats as free.

**Commit chain** - a set of file writes that upon close() or flush() will become a new file, replace an existing file, or will replace the tail of an existing file. The blocks of the chain are written as the file grows; the first block of the chain (the head of a new or replaced file, or the fork block of an appended file) is activated last, and that one write is the commit.

**Inactive copy** - the head block of a file opened with "w+" is held in the handle's buffer and has no copy on the flash until the first time it is rewritten. A copy that has been written stays inactive until close() or flush() commits the file. The block table records "no copy on the flash" for such a head with an address outside the filesystem (the value BLOCKS), so a rewrite of it cancels nothing.

**Flash Erase** - the Flash chip supports erasing a block at a time. A block is 4096 bytes. An erase of a block returns all bits of the block to 1 ($FF in all bytes of the block)

**Flash Write** - a flash write only changes 1 bits to 0's. If a bit is 0 it can not be changed until the block containing it is erased at which the time bit becomes 1 once again.

**Life Cycle** - a 3-bit field within each of our blocks that indicates precedence of blocks having the same **block ID**.

## File System Block Types and Formats of these Blocks

The first long (4-bytes) of each block (addr $000-$003) identifies the block Id, the structure of the remaining bytes in the block, the location of the block within a chain of blocks that comprise a single file, as well as the state of the block.

 
The bits of this first long in the block are interpreted as follows:

| Bit location | xx | xx |
| --- | --- | --- |
| 31..20 | EndPtr -or- NextId | 12-bit field: EndPtr is address of next free byte in block<br>NextID is Block ID of next block in chain 
| 19..8 | ThisID | the Block ID [0-3967] assigned to this block
| 7..5 | LifeCycle | life-cycle state of this block
| 4..2 | Unused | these bits reserved
| 1..0 | Block Type | bit 1x = head/body, bit x1 = last/more <br>which yields: 00 = head/last, 01 = head/more, 10 = body/last, 11 = body/more

The LifeCycle  3-bit field describes the state of the block as inactive, canceled, or active. Active and Canceled LifeCycle values follow rules which are based upon the fact that 1-bits can only transition to 0 on a flash device.  These rules are:

- Active block values follow the single-zero ring counter state sequence: 011..101..110..repeat
- Of two blocks with identical IDs, the valid block is the one whose state comes later in that ring. The order is a ring, not a numeric one: 011 is later than 110.
 (Which allows for make-before-break block replacement that can be recovered after unexpected power loss)
- To cancel a block the driver clears all three life-cycle bits (it writes 000). Any value with two or more zeroes reads as canceled, and the block is then free again.

This is an overview of the possible values of the three bits:
 
| bit value | meaning | how to recognize
| --- | --- | --- |
| 111 | inactive | no zeroes
| 011/101/110 | **active** | one zero
| 001/010/100/000 | canceled | two or three zeroes

**NOTE1**: A life cycle field transitions from Inactive/formatted (no zero bits) to Active (1 zero bit) to canceled (2 or more 0 bits).

**NOTE2**: When blocks are duplicated with the intent of the newer replacing the older then the active life cycle value transitions from 3 (011) -> 5 (101) -> 6 (110) -> 3 (011) -> ... forever. A rewritten or moved block takes the next value of the block it replaces; a new file's blocks start at 3 (011).

This is how we determine age of two blocks with identical Block IDs but the life-cycle bits are different. When we find these we want to finish the transaction by cancelling the older of the two blocks having these matching IDs. The driver assumes no ID is held by more than two blocks.

| newer block | older block | note
| --- | --- | --- |
| 011 (3) | 110 (6) | the ring wrapped from 6 back to 3
| 101 (5) | 011 (3) |
| 110 (6) | 101 (5) |


Blocks written to our flash filesystem are of the following formats:

| byte offset (hex) | purpose | notes |
| --- | --- | --- |
| **Head/Last block** 
| 000..003 | long {EndPtr[11:0], ThisID[11:0], %vvv11100} | vvv = lifecycle, 00 = head/last
| 004..007 | long {DataOffset[11:0]} | offset to data in block (in bytes[4:5])
| 004..007 | long {FilenameCRC19[31:12]} | crc19 of filename + terminator (in bytes[5:7])
| 008..087 | byte filename[127+1] | filename + terminator
| 088..FFB | byte data[3956] | data
| FFC..FFF | long crc32	 | crc32 of 000..FFB
| **Head/More block** |
| 000..003 | long {NextID[11:0], ThisID[11:0], %vvv11101} | vvv = lifecycle, 01 = head/more
| 004..007 | long {DataOffset[11:0]} | offset to data in block (in bytes[4:5])
| 004..007 | long {FilenameCRC19[31:12]} | crc19 of filename + terminator (in bytes[5:7])
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

The file's control data also contains logical next pointers in each block except the last block. These next pointers contain the block ID of next block that is part of this file. We use block IDs instead of block addreses so the blocks containing the ID can be replaced with another block having the same ID when the file content changes but the block pointing to this ID don't have to change. 

A file made up of these blocks can exist in one of three shapes:

| Constituency | Max size | Notes
| --- | --- | --- |
| Head/Last block | 3,956 bytes | 1 block file
| Head/More block -> Body/Last block | 8,044 bytes | 2 block file
| Head/More block -> (1 or more) Body/More block -> Body/Last block | 16,221,052 bytes | up to a 3,968-block file

**NOTE1**: the largest file would be a 1 x **Head/More block** (3,956 bytes) -> 3,966 x **Body/More block**s (4,088 bytes ea.) -> 1x **Body/Last block** (4,088 bytes) which yields a max length of 16,221,052 bytes.

**NOTE2**: Given this block-type composition of our files, our flash chip using this system can contain a **maximum** of 3,968 **files** ea. 1 block, 3,956 bytes each.

#### File open(filename, mode) Supported Modes

| Open Mode | supports seek() | description |
| --- | --- | ---|
| <pre>read [%"r", %"R"]</pre>  | YES | Read from an **existing file**,<BR>Supports direct access via seek() |
| <pre>write [%"w", %"W"]</pre>   | no | Write to a **new file**, creating it (or write to an **existing file**, replacing it.) The existing file stays on the flash, untouched, until close() or flush() commits what was written. A file closed with nothing written is not created, and an existing file of that name is **deleted**. <br>Use `if exists(@"filename") ...` to avoid overwriting an existing file |
| <pre>append [%"a", %"A"]</pre> | no | Write to an **existing file**, extending the existing file. If the file didn't exist then this becomes a write ["w", "W"]. Closed with nothing written, an existing file is unchanged. |
| <pre>read/modify [%"r+", %"R+"]</pre> | YES | Read Extended from, Write Extended to an **existing file**, extending the existing file by writing records at end, and/or modifying the middle of the file by seeking to a location, overwriting a record at that location within the existing file. The file is modified in place. <BR>Supports direct access via seek()|
| <pre>write/modify [%"w+", %"W+"]</pre> | YES | Write Extended to a **new file**, creating it (or write Extended to an **existing file**, replacing it.) Use `if exists(@"filename") ...` to avoid overwriting an existing file. <BR>Extend the file by writing records at end, then modify already written parts of the file by seeking to a location, and overwriting a record at that location. The original file is replaced when the new file is committed by close() or flush(), and **deleted** if nothing was written.<BR>Supports direct access via seek() |

Every open mode, on a new file and on an existing file, is traced in the README's "Differences from ANSI C" section. Any other mode, such as "a+", returns E_FILE_MODE.


#### Writing to a File

- A filestarts out as a **Head/Last block** and remains so while it is <= 3,956 bytes.
- When file gets to 3,957 bytes, the 3,956+1 byte is written to a **Body/Last block** and the **Head/Last block** is rewritten as a **Head/More block**
- When the file then gets to 3,956+4,088+1 (the 8,045th byte) is written to a new **Body/Last block** and the current **Body/Last block** is rewritten as a **Body/More block**.
- ... and so on ...

#### Appending to an existing File

When appending there are really two cases with the more normal case being the first:

- **Case #1**: In the case of appending to a longer file (a file which is 2 or more blocks) then the append consists of wirting to the **Body/Last block** until we attmpt to write the byte just past then end of this block. At this time we allocate a new **Body/Last block** to contain this new byte and rewrite the prior **Body/Last block** as a **Body/More block**.

The less frequent case is when we append to a file that contains less than 3,956 bytes:

- **Case #2**: In the case of a small file we write into the (**Head/Last block**) until we fill it. Thie growth of this file follows the seqence shown in  "Writing to a File" (above.)

#### Replacing records within a File

When replacing records (regions of bytes) within a file, we seek to the location of the record and write **new record content** to replace the previous content.  If our seek took us to the end of the current file, we then write the new record content at the end of the file. This is logically an append of a record to the current file.

Internally this is all handled very simply. The user seeks to the location in the file. The seek locates the block containing the byte at the seek address which is then loaded into our block buffer for the file handle.  The next writes then are written to this block in the handle buffer. If we attempt to write beyond the end of this block (or we seek to a location outside of this block) then the modified block is written to a free block with the same block ID and the next life-cycle value, activated, and the block it replaces is cancelled. The new block is then loaded into the buffer either where we continue the current write or are ready for the next write. A seek to a position past the end of the file is refused with E_FILE_SEEK, so a write never leaves a gap; a seek to the end of the file (POSX) is allowed, and a write there extends the file.

Replacing is different from writing or appending in that in this "extended" file mode (R+, W+) the changes are made one block at a time: a rewrite of a block is its own commit, and the file's chain of blocks is the same before and after it. For R+ that is true from the first write. For W+ the file as a whole is not committed until close() or flush(); see below.

When there is no free block for a rewrite, nothing is changed: the old block stays on the flash, the modified block stays in the handle's buffer, and the call that needed the rewrite (a seek, a read, a write that runs into the next block, a flush() or a close()) returns E_DRIVE_FULL.


#### BEHAVIOR: Writing, Overwriting, Appending

When a file is opened for sequential writing all the writes are accumulated into what we call a "commit chain". As a commit chain block fills it is written to the filesystem, but only while a second free block is left for the block that follows it; with none left the write stops with E_DRIVE_FULL and the full block stays in the handle's buffer. Upon close() or flush() the last block is written to the filesystem. Lastly, the commit chain head block is activated: that one write is the commit. If there was a prior file (we are overwriting or appending) then the commit head block will supercede the prior files block and the prior block(s) will be deleted. If the power fails just before the head is activated, the blocks of the chain are never reached from any file, and mount() cancels them as unreached (a replaced or appended file is still there whole). If the power fails after the head is activated but before the older block is cancelled, the block will be discovered (block of same ID but with newer lifecycle) at mount and the older block will be canceled during the mount.

A close() or flush() that finds no free block for the last block writes nothing and activates nothing: the file stays as it was at its last commit (a new file is not created), and the call returns E_DRIVE_FULL. A flush() keeps the handle and the unwritten bytes, so a later flush() or close() can commit them once a block is free; a close() frees the handle and the bytes are lost.

##### Actions unique to open() mode

When we **open(filename, %"W")** and **there is no prior file** (Write) then we are creating a new file. In this case there is no prior block to be replaced at close.


When we **open(filename, %"W")** and a **prior file DOES exist** (Replace) then we are also creating a new file but upon close we are replacing the prior file, deleting all the blocks associated with the prior file. The prior file is not touched at open. If nothing was written when the file is closed, there is nothing to replace it with, so the prior file is deleted (a file with no contents does not exist), close() returns SUCCESS and error() holds SUCCESS.

When we **open(filename, %"W")** or **open(filename, %"A")** with **no prior file** and close it with nothing written then no file is created: nothing was ever activated, and the block ID taken for its head is given back.

When we **open(filename, %"A")** and **there is no prior file** (Write) then we are creating a new file. In this case there is no prior block to be replaced at close.

When we **open(filename, %"A")** and a **prior file DOES exist** (Append) then we are opening the file, seeking to the end and then writing bytes beyond the end of the original file. Upon close the commit head block will be activated to replace the tail block of the original file.

When we **open(filename, %"W+")** and a **prior file DOES exist** (Replace) then we are also creating a new file, which the prior file does not affect: the prior file stays whole on the flash, and exists() and file_size() keep reporting it, until the new file is committed by close() or flush(). The head block of the new file is written with the head block ID of the prior file and its next life-cycle value, so activating it makes the new head supersede the old one in a single write. Only then is the chain of the prior file cancelled. A power loss before that write leaves the prior file (the new file's body blocks are cancelled as unreached by mount()); a power loss after it leaves the new file (mount() keeps the newer of the two heads). If the file is closed with nothing written, the prior file is deleted, as for "W".

When we **open(filename, %"R+")** the file is modified in place: nothing about the file changes at open, and each block that is modified is rewritten when the handle moves off it or at flush() and close().


#### BEHAVIOR: Seeking within a File opened for Read, Read/Modify or Write/Modify

Seeking within an existing file is supported without any control structures being recorded/or updated within the file itself. A seek pointer is maintained for the open file handle. When a seek is requested the location is stored in the handle state data and the block underlying that location is loaded into the handle's buffer. When a read follows the seek the seek pointer is updated with the length of the data read.

Each handle also keeps a small seek cache: the ID of the block its last seek (or size count) found, and that block's file offset. The next seek walks the chain on from the cached block when the target is at or beyond it, instead of from the head of the file. A block keeps its ID when it moves, so the cache names the block by ID; it is emptied whenever the chain can lose a block or change its head (open, close, a flush that commits, mount).

In "r+" and "w+" mode the bytes written past the end of the file and not yet flushed are part of the file, and a seek can reach them. Seeking to the end of an empty file gives position 0. A seek relative to the current position counts from the true file offset of the handle.

A handle opened with "w" or "a" does not seek: those modes write at the end only.

#### BEHAVIOR: Treating a file as a Circular Buffer

Maintaining an existing file in a circular fashion is supported without any control structures being recorded/or updated within the file itself.  We are implementing this very simply, two new open methods provide the functionality. When **opening for append** or **opening for read** you will **specify the max length of the file** (logically, when you want it to wrap.)  We accomplish the wrap by always appending to the end of the file and removing the head block keeping the file at your desired fixed length. Let's look at this in slightly more detail.

##### File open_circular(filename, mode, max\_file\_length) supported Modes

| Open_circular() Mode | supports seek() | description |
| --- | --- | ---|
| <pre>read [%"r", %"R"] limit</pre> | YES | Read from an **existing file**, from its first byte. A circular file is trimmed to **max\_file\_length** each time it is committed, so its first byte is the oldest byte kept. For a file written by v1.4 (an old-format head block) that is longer than max\_file\_length, the first byte read is exactly max\_file\_length from the end of the file. |
| <pre>append [%"a", %"A"] limit </pre>  | no | Write to an **existing file**, extending the existing file. If the file didn't exist it will be created, upon close() or flush() if the file exceeds limit then the file will be froncated (truncated from the front) leaving limit bytes, from the tail of the file, active |

Under the covers this circular behavior affect reads and writes. When **opened for read as circular** the first data returned is from the front of the file. The trim at each commit (below) has already removed what lies before the front of your circular buffer. A v1.4 file was not trimmed this way: when one is longer than the limit, the first data returned is at the (file length - max size) offset, and seek positions count from there.

When the file is **opened for write as circular** after the writes are completed and the file is being closed or flushed then the entire write commit chain is written to flash. After this file is complete on flash then the file is froncated (Front Truncated) removing any/all leading blocks leaving enough blocks to contain the **max\_file\_length** bytes at the tail of the file blocks. If any blocks are removed during Froncation this means the file head block effectively moves to be the new leading block of the file blocks not removed during this Froncate process. A trimmed file's size, as file_size() and file_size_for_handle() report it, is the length that can be read from it: the bytes the trim dropped from the first kept block are not counted.

The trim needs a free block. A flush() whose trim finds none leaves the file committed and whole over its limit and returns E_DRIVE_FULL; the handle remembers that the trim is owed, and the close() that follows retries it even when nothing more was written.

A circular file written by v1.4 (whose head block records no data offset) is read with open_circular() through a window that starts at the first byte the limit keeps. Seek positions and file_size_for_handle() for such a handle count from the start of that window.

#### BEHAVIOR: Treating a file as Modifiable (replacing records within a file)

File content modification is supported if a file is opened in the Extended Read (R+) or Extended Write (W+) mode.  

In this mode, we think of the file as containing records. Open the file, seek to a location, read the exsting record, make a change in it, then seek back to the record location and write the newly modified record.  We can do this anywhere within the existing file or we can append records the the file.

In the case of the **Write Extended** (W+) mode we must first append records then we can seek within the records written, replacing records as we need. The file is new: it does not exist for exists(), file_size() or any other call until close() or flush() commits it, and an existing file of the same name is left whole until then.

There are really only two underlying forms of transactions when handling extended file writes.  

- **Case #1**: the record being replaced fits entirely within a block. In this case when we close(), flush(), or seek to another location away from this block the current modified block buffer contents are written to a new block with the same block ID, but the next LifeCycle value of the block it is replacing. After the block is written and activated, the prior block is cancelled.

- **Case #2**: The record being replaced overflows from the current block into the next block. In this case, as we run off the end of the current buffer we have to write the first part of the record by replacing the block containing it. The current modified block buffer contents are written to a new block with the same block ID, but the next LifeCycle value of the block it is replacing. After the block is written and activated, the prior block is cancelled. Then we resume the record write by loading the next block and continuing to write the remainder of the record into the buffer containing this next block. Lastly, when we close(), flush(), or seek to another location away from this block the current modified block buffer contents are written to a new block with the same block ID and the next LifeCycle value of the block it is replacing. After the block is written and activated, the prior block is cancelled.

A write at or past the end of the file extends it, as C's `r+` does, in both modes. Within the last block the end pointer moves with the write. When the last block is full, a new last block holding the next byte is written and activated first, and only then is the full block rewritten with a link to it, so the chain on the flash is whole at every step. That needs one free block ID and two free blocks; without them the write stops with E_DRIVE_FULL and nothing more changes. A "w+" file has one difference in how its first block is handled: while the file is uncommitted, the head block is rewritten as an **inactive copy** (see Concepts), because activating it is what makes the file exist. close() or flush() writes the modified body block, then activates the head, and cancels the chain of any file it replaces. When close() finds no free block to commit a new "w+" file, it cancels the inactive head copy and the body blocks it links to, and frees their IDs, so the next mount() finds nothing to remove. After a flash fault they are left as a power loss would leave them. A flush() that cannot commit keeps them, so a later flush() or close() can commit once a block is free.


## Tracking Data (State of Filesystem)

When the filesystem is first mounted the following 3 tables are zeroed and then populated by mount() as it scanns all the blocks in the space allocated to the filesystem. The tables are:

### Table IDtoBlocks: ID to Block translation

This table is initialized to zeros and filled-in when mount() is called. This table is indexed by blockID and returns a blockAddress (The block containing that ID is found at filesystem location blockAddress.)

**Physically** this table is a contiguous allocation of WORDs. Its size is calculated so that it can contain a 12-bit variable for each block allocated to the filesystem which is then rounded up to nearest WORD boundary.

```spin2
CON     ID_TO_BLOCKS_SZ     = (BLOCKS * 12 + 15) / 16
DAT     IDToBlocks  WORD    0[ID_TO_BLOCKS_SZ]  ' ID-to-block translation table
        IDToBlock   LONG    0                   '(field pointer)
```

A block ID that has no copy of its block on the flash yet (the head of a new "w+" file, see Concepts) holds the value BLOCKS, an address one past the last block of the filesystem.

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
CON     FLAGS_SIZE          = (BLOCKS * 1 + 7) / 8
DAT     IDValids  BYTE    0[FLAGS_SIZE]    'ID-valid flags
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

This table is initialized to zeros and filled-in when mount() is called.  This table is indexed by blockAddress (offset into the filesystem) and returns a blockState enum value [B_FREE, B_TEMP, B_HEAD, B_BODY]. B_TEMP is a block that is in use but not part of an active file: one a writer has taken and not yet activated, or an active block no file reaches. B_HEAD and B_BODY are the head block of a file and any later block of it.

**Physically** this table is a contiguous allocation of BYTEs which consists of 1 byte for every 4 valid block address, 2 bits per block address. Its size is calculated so that it can contain a 2-bit variable for each block allocated to the filesystem which is then rounded up to nearest BYTE boundary.

```spin2
CON     STATES_SIZE         = (BLOCKS * 2 + 7) / 8
DAT     BlockStates BYTE    0[STATES_SIZE]   'block states
        BlockState  LONG    0                '(field pointer)
```

**Logically** this table is treated as a contiguous array of 2-bit variables indexed by blockAddress (**NOTE**: this is NOT blockID!).
Each 2-bit variable contains a block state enum value [B_FREE, B_TEMP, B_HEAD, B_BODY].  
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

For each open file (handle) the driver maintains the following information:

| Name |Allocation | Purpose | Notes
| --- | --- | --- | --- |
| | **File State tracking**
| hStatus | BYTE    0[MAX\_FILES_OPEN] | handle: open mode bits, a combination of H\_READ, H\_WRITE, H\_FORK and H\_MODIFY (0 is not in use)| 1 byte
| hHeadBlockID | WORD    NOT\_VALID[MAX\_FILES_OPEN] | handle: first blockID of file chain | 2 bytes
| hEndPtr | WORD    0[MAX\_FILES_OPEN] | handle: pointer to next write byte in block (or $FFC if block full) | 2 bytes
| hFilename | BYTE    0[MAX\_FILES_OPEN * FILENAME\_SIZE] | handle: 127+1 byte buffer for filename | 128 bytes
| hBlockBuff | BYTE    0[MAX\_FILES_OPEN * BLOCK\_SIZE] | handle: 4KB buffer for file data | <pre>4096 bytes</pre>
| hModified | BYTE    0[MAX\_FILES_OPEN] | T/F where T means the buffer has been modified and needs to be written to flash | 1 byte
| | **Commit-chain tracking**
| hChainBlockID | WORD    0[MAX\_FILES_OPEN] | handle: first blockID of commit chain | 2 bytes
| hChainBlockAddr | WORD    0[MAX\_FILES_OPEN] | handle: first block_address of commit chain | 2 bytes
| hChainLifeCycle | BYTE    0[MAX\_FILES_OPEN] | handle: first block lifecycle (cycle value for replacement first block of commit chain) | 1 byte
| hHeadPending | BYTE    0[MAX\_FILES_OPEN] | handle: T while the head block of a "w+" file is not yet active on the flash | 1 byte
| hReplacedID | LONG    NOT\_VALID[MAX\_FILES_OPEN] | handle: head block ID of the existing file this handle replaces at close, or NOT\_VALID | 4 bytes
| | **Special Mode tracking**<br>**(Seeking, Circular files)**
| hSeekPtr | LONG    NOT\_ENABLED[MAX\_FILES_OPEN] | handle: seek address within active block | 4 bytes
| hSeekFileOffset | LONG    0[MAX\_FILES_OPEN] | handle: logical seek address within entire file | 4 bytes
| hCircularLength | LONG    0[MAX\_FILES_OPEN] | handle: circular buffer length in bytes | 4 bytes
| hTrimPending | BYTE    0[MAX\_FILES_OPEN] | handle: T while a committed circular file is over its limit because its trim found no free block | 1 byte
| hWindowStart | LONG    0[MAX\_FILES_OPEN] | handle: file offset of the first byte of an old-format circular read, 0 for every other handle | 4 bytes
| hCacheBlockID | WORD    NO\_CACHED\_BLOCK[MAX\_FILES_OPEN] | handle: seek cache, the ID of the block the last locate found | 2 bytes
| hCacheStart | LONG    0[MAX\_FILES_OPEN] | handle: seek cache, the file offset of that block's first data byte position (negative for a head block with a data offset) | 4 bytes
| hCacheOldFmt | BYTE    0[MAX\_FILES_OPEN] | handle: seek cache, T when the file's head block is old format | 1 byte
| | | | **4,264 bytes / handle**


## The Format Process [F]

Formatting the Flash is a simple process. The first byte of every block allocated to the flash fileystem is read and if the lifecycle bits indicate the block is active [%011, %101, or %110] then the block is "canceled." That is the lifecyle bits are set to %000 and the byte is written to flash. Once this is complete all blocks will be seen as not in use when the mount occurs. format() then mounts the filesystem, and holds the lock from before the first block is cancelled until that mount is done, so another cog's call finds either E_NOT_MOUNTED or the formatted filesystem fully mounted. Every handle is freed, so a file that was open is abandoned.

## The Mount Process [M]

Upon Mount the entire flash space is scanned for well-formed blocks and work is completed if found incomplete. All files are located. Lastly any badly formed blocks/block chains are freed. In this last case an error code is returned from mount.  Here's a bit more detail. Mount makes three passes over the blocks, and reads each active block whole only once, in the first:

### [M1] Initial scan

The first step in the mount process reads the first byte of every block. A block whose lifecycle is active is then read whole (4,096 bytes) and checked:

- its 32-bit CRC must match, and
- its ThisID, its NextID (when it has one), its EndPtr (when it is a last block) and, for a head block, its data offset must all lie in range: an ID is 0..3,967, an EndPtr lies in the data area of its block, and a data offset leaves the EndPtr at or past the data it skips.

A block that fails either check is "canceled" and stays free. A CRC can match a block whose fields no block this driver writes would hold, so the range check is what keeps a damaged block's IDs from indexing past the tables.

For a good block, the block is marked B_HEAD when it is a head block and B_TEMP when it is a body block, and its ID is marked in use. If the ID is already in use by another good block, there is a duplicate: the block with the higher priority (the newer lifecycle value) is kept while the block with the lower priority is "canceled.".  In actuality, there should only ever be one occurance of this. A 2nd case should never be found. This one occurance would be due to a power failure occurring after the block with the higher priority was written but before the block with the lower priority could be canceled. The driver assumes no ID is held by more than two blocks.

This step in the mount process effectively finishes the work that didn't complete due to a power failure.

A side effect of this step is that any blocks that have an active lifecycle but an invalid CRC are marked as canceled. Thus inhibiting future CRC checks for these blocks.

### [M2] Locating complete files and canceling incomplete

This next step uses the product of the first step. The first step left indications of which blocks are valid within the entire space allocated to the flash filesystem, and it marked every head block B_HEAD, so no block is read again to find them.  This step then iterates over the B_HEAD blocks and walks each file chain from its head, marking the blocks it reaches B_HEAD or B_BODY.

A chain is broken, and the file removed, when it names a NextID that is not a block ID, names an ID no good block holds, reaches a head block, or runs longer than the number of blocks. A broken chain is walked again to return the blocks it reached to B_TEMP.

The end product of this seach is that all file locations are now known in addition to which blocks belong to files.  We also know if any blocks are somehow active but no longer belong to any files.

### [M3] Clearing blocks that no longer read correctly

The final pass then clears the blocks still marked B_TEMP, the active blocks no file reaches, by canceling each of them effectively marking each of them as free/not in use.  The body blocks written for a file whose head was never activated are such blocks. This "clearing" of damaged blocks is not a normal case. It only happens when the flash memory has somehow changed state (or aged.). In the case of blocks being found during the mount effort and then canceled an error code **E\_BAD\_BLOCKS_REMOVED** is returned from the mount call: for a block whose CRC did not match, for a block with an out-of-range field, and for a block no file reaches. A duplicate ID alone, which a power loss during a block move leaves, is resolved with no status: mount() returns SUCCESS. This is to allow and application to be able to detect if files are somehow being lost to the aging effects of the flash chip.

can_mount() makes the same reads and the same checks without changing any block. It answers TRUE when mount() would change no block, and FALSE with E_BAD_BLOCKS_REMOVED for a bad block or an unreached one. A duplicate ID alone gives FALSE with error() SUCCESS: a mount would resolve it. A filesystem that is already mounted would not change, so can_mount() answers TRUE. When the check cannot be made, can_mount() answers FALSE and error() holds the reason: E_NO_HANDLE or E_BAD_HANDLE for a driver built with a `MAX_FILES_OPEN` below 1 or a `HANDLE_BASE` other than 0 or 1 (even when mounted), E_NO_LOCK_AVAIL when no hub lock was free, and E_FLASH_TIMEOUT when the chip was still busy.

A mount builds the tables from the flash and frees every handle. A filesystem that is already mounted is left as it is: mount() returns SUCCESS and the open files stay open.

## Locating a next block to allocate to a file [L]

Our wear leveling is accomplished by two mechanisms:

1. The first is by how we choose a block to be allocated. We randomly pick a block from within the entire flash filesystem space, skipping blocks that are B_TEMP (taken by a writer and not yet activated, so never moved). The pick is made first; the free blocks are counted only as far as the pick needs.
2. The 2nd mechanism then ensures the leveling. Once the new location is randomly determined then if the block is already in use (B_HEAD or B_BODY) we relocate the contents of this block to another randomly picked open location and continue to place our new content in this first random location. The copy takes the next life-cycle value and is activated at once, so it supersedes the original, and then the original is cancelled: a power loss between the two leaves a duplicate ID that mount() resolves.

A block that is picked and is free is taken at once when no spare block is asked for. A block written when a next block must follow it asks for one spare free block, so the block after it can always be written. When too few blocks are free the result is E_DRIVE_FULL and no table and no block is changed.

## Locking: how cogs share the filesystem [K]

Every public method that reads or changes the filesystem holds one hub lock for the whole call: it takes the lock, checks that the filesystem is still mounted (another cog's unmount() may have run while this one waited), does its work, and releases the lock. A call therefore runs from start to finish before any other cog's call starts. The README's "Multi-cog use" section states what that means for a program.

- **Taking the lock.** A cog spins on LOCKTRY until it gets the lock. The driver keeps no queue and makes no claim about which waiting cog gets the lock next: that is up to the hub. A cog could in principle wait through many other cogs' calls.
- **Creating the lock.** The first mount(), format() or can_mount() of the run finds no lock, and the cogs that call at about the same time hold an election: each cog writes its system counter into its slot, waits 10 ms for other cogs to arrive, and the cog with the lowest count (the lower cog ID on a tie) asks the hub for a lock with LOCKNEW. The others wait until the lock exists. If the hub has no free lock, every cog in the election returns E_NO_LOCK_AVAIL and the next call elects again.
- **Keeping the lock.** The lock is kept from the first mount() until reset or power-off. unmount() does not return it. The driver launches no cog and has no stop call, so there is no later point at which to return it, and it uses exactly one of the hub's 16 locks.
- **Checks before the lock.** Every call that needs a mounted filesystem tests that before it takes the lock, and a call that takes a filename tests the name there too, so such a failing call returns at once. The handle and the count of `read()`, `write()` and the typed `rd_`/`wr_` calls are tested once the lock is held. Each of these calls tests the mount again once it holds the lock.
- **Per-cog results.** error() is kept for each cog, so one cog's failed call never changes what another cog reads from error().

The tables, the handle arrays and the block buffers are in DAT, shared by every cog. A handle belongs to the program, not to a cog: any cog can use a handle another cog opened, and the lock serializes the calls.

## Device faults [D]

A flash erase or program that the chip does not finish within the bound (1 second, set against the datasheet's 400 ms maximum for a 4 KB erase and 3 ms for a page program) is a device fault, as is a request to program a block outside the filesystem. The call that finds it returns E_FLASH_TIMEOUT, and the filesystem is left unmounted: every handle is freed with no commit, and every later call returns E_NOT_MOUNTED until mount() or format() is called. Nothing already written is undone, so the flash is as a power loss at that step would leave it, and the next mount() recovers it: it keeps the older or the newer of two copies, and cancels blocks no file reaches. Data a handle held that had not been written to the flash is lost, in every open file. mount() waits for the chip to finish any erase or program a failed wait left running before it reads a block.

## This is my second ...

This is my second version of this Theory of Operations Document. If I've not covered something here that you would like to see please let me know by filing issue, contacting me directly or by posting your request in our P2 Forums.

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

Licensed under the MIT License.

Follow these links for more information:

### [Copyright](copyright) | [License](LICENSE)

[maintenance-shield]: https://img.shields.io/badge/maintainer-stephen%40ironsheep%2ebiz-blue.svg?style=for-the-badge

[license-shield]: https://camo.githubusercontent.com/bc04f96d911ea5f6e3b00e44fc0731ea74c8e1e9/68747470733a2f2f696d672e736869656c64732e696f2f6769746875622f6c6963656e73652f69616e74726963682f746578742d646976696465722d726f772e7376673f7374796c653d666f722d7468652d6261646765
