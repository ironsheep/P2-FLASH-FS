# P2-FLASH-FS / Regresssion Tests

![Project Maintenance][maintenance-shield]

[![License][license-shield]](LICENSE)

These are regression test files that I'm using to certify the FS operation with each release.  All tests must pass! The regression test programss are versioned here so you can repeat this testing any time to verify your driver operation.

The point of these tests is to exercise each method attempting to check both normal and error/exception cases.

## Test Coverage

The Regression test coverage is nearly complete!  This table indicates which methods have been test by the current regression test programs.

| Public Method | tested | Notes
| --- | --- | --- |
| PUB version() : result | YES
| PUB serial_number() : snHi, snLo | YES
| PUB mount() : status | YES
| PUB unmount() | YES
| PUB format() : status | YES
| PUB error() : result | YES
| PUB open(p_filename,"r") : handle | YES
| PUB open(p_filename,"w") : handle | YES
| PUB open(p_filename,"a") : handle | YES
| PUB open(p_filename,"r+") : handle |
| PUB open\_circular(p_filename,"r") : handle |
| PUB open\_circular(p_filename,"a") : handle |
| PUB close(handle) : status | YES
| PUB rename(p_old_filename, p_new_filename) : status | YES
| PUB delete(p_filename) : status | YES
| PUB exists(p_filename) : result | YES
| PUB file\_size(p_filename) : size_in_bytes | YES
| PUB file\_size_unused(p_filename) : size_in_bytes_unused | YES
| PUB seek(handle, position) : result | YES
| PUB write(handle, p_buffer, count) : result | YES
| PUB wr_byte(handle, byteValue) : result | YES
| PUB wr_word(handle, word_value) : result | YES
| PUB wr_long(handle, long_value) : result | YES
| PUB wr_str(handle, p_str) : result | YES
| PUB read(handle, p_buffer, count) : bytes_read | YES
| PUB rd_byte(handle) : value | YES
| PUB rd_word(handle) : value | YES
| PUB rd_long(handle) : value | YES
| PUB rd_str(handle, p_str, count) : result | YES
| PUB directory(p_block_id, p_filename, p_file_size) | YES
| PUB stats() : usedBlocks, freeBlocks, fileCount | YES
| PUB string_for_error(error_code) : p_interpretation | YES


## Running the tests

In order the compile the tests you need to uncomment the test-support routines in `Draft_flash_fs.spin2`. Look for line 1705:

#### Driver file: Draft\_flash\_fs.spin2: line 1705
```spin2
{   ' REMOVE BEFORE FLIGHT: uncomment this line before release!!!

' ----------------------------------------------------------------------------------------------
'   these methods are for regression testing only - they are not used in production code
```
comment out the 1st line to enable the code that follows. [ place a ' before the {... ]


#### Determine debug output routing (RT_*.spin2 files)

At the head of each of test RT .spin2 files you want to run look for the debug output lines:

```spin2
{
    ' debug via serial to RPi (using RPi gateway pins)
    DEBUG_PIN_TX = 57
    DEBUG_PIN_RX = 56
    DEBUG_BAUD = 2_000_000
'}
```

These lines when uncommented route the debug serial to PINs 57/58 which I connect to the a Raspberry Pi for logging as there is lot of output from the test runs.

In their present for (commented out) the debug output just goes the debug window on windows where you are running the compiler.


## The Test files 

This is a recap of the version history of these files:

| Date | Status |
| --- | --- |
|  <PRE>2023-Aug-26</PRE> | Initial release. `RT_read_write_tests.spin2`<br>Working Format, Mount, open(file, "R"), open(file, "W"), close(),<br>Focused tests for wr\_byte(), rd\_byte(), wr\_word(), rd\_word(), wr\_long(), rd\_long(), wr\_str(), and rd\_str() <br>Spanning blocks tests need to be added|
|  <PRE>2023-Aug-27</PRE> | More Tests: `RT_read_write_block_tests.spin2`<br>Working Format, Mount, open(file, "R"), open(file, "W"), close(),<br>Focused tests for read(), write(), and file\_size_unused(): in only block, spanning two blocks, spanning 3 blocks |
|  <PRE>2023-Aug-28</PRE> | More Tests: `RT_read_seek_test.spin2`<br>Working Format, Mount, open(file, "R"), open(file, "W"), close(),<br>Focused tests for seek(): in only block, spanning two blocks, spanning 3 blocks |
|  <PRE>2023-Aug-29</PRE> | **Updated** `RT_read_write_tests.spin2`<br>Working Format, Mount, open(file, "R"), open(file, "W"), close(),<br>Focused tests for wr\_byte(), rd\_byte(), wr\_word(), rd\_word(), wr\_long(), rd\_long(), wr\_str(), and rd\_str() <br>Added tests for version(), serial_number(), directory(), and 2, 3 block span tests using longs |


## Test files by Stephen

This is my work in progress as I'm working toward customer facing release of the FileSystem code


| File | Purpose |
| --- | --- |
| [RT\_utilities.spin2](RT_utilities.spin2) | Utility methods common to all Test Files |
| [RT\_read\_write_tests.spin2](RT_read_write_tests.spin2) | The read/write basic types test suite |
| [RT\_read\_write_tests.log](RT_read_write_tests.log) | Log of the read/write basic types tests [82 passes, 0 fails] |
| [RT\_read\_write\_block_tests.spin2](RT_read_write_block_tests.spin2) | The read/write records(blocks) test suite  |
| [RT\_read\_write\_block_tests.log](RT_read_write_block_tests.log) | Log of the read/write records(blocks) tests  [39 passes, 0 fails]<br>(*42 successes (+3) were extra checks I did for 3 tests*) |
| [RT\_read\_seek_test.spin2](RT_read_seek_test.spin2) | The read/write seek test suite |
| [RT\_read\_seek_test.log](RT_read_seek_test.log) | Log of the read/write seek tests [61 passes, 0 fails] |

### Next Steps:

- finish tests for append modes
- finish tests for read-modify write modes
- finsih tests for multi-cog reads/writes 
- ...

---

> If you like my work and/or this has helped you in some way then feel free to help me out for a couple of :coffee:'s or :pizza: slices!
>
> [![coffee](https://www.buymeacoffee.com/assets/img/custom_images/black_img.png)](https://www.buymeacoffee.com/ironsheep) &nbsp;&nbsp; -OR- &nbsp;&nbsp; [![Patreon](../DOCs/images/patreon.png)](https://www.patreon.com/IronSheep?fan_landing=true)[Patreon.com/IronSheep](https://www.patreon.com/IronSheep?fan_landing=true)

---

## Disclaimer and Legal

> *Parallax, Propeller Spin, and the Parallax and Propeller Hat logos* are trademarks of Parallax Inc., dba Parallax Semiconductor
>
> This project is a community project not for commercial use.
>
> This project is in no way affiliated with, authorized, maintained, sponsored or endorsed by *Parallax Inc., dba Parallax Semiconductor* or any of its affiliates or subsidiaries.

---

## License

Copyright © 2022 Iron Sheep Productions, LLC. All rights reserved.

Licensed under the MIT License.

Follow these links for more information:

### [Copyright](copyright) | [License](LICENSE)

[maintenance-shield]: https://img.shields.io/badge/maintainer-stephen%40ironsheep%2ebiz-blue.svg?style=for-the-badge

[license-shield]: https://camo.githubusercontent.com/bc04f96d911ea5f6e3b00e44fc0731ea74c8e1e9/68747470733a2f2f696d672e736869656c64732e696f2f6769746875622f6c6963656e73652f69616e74726963682f746578742d646976696465722d726f772e7376673f7374796c653d666f722d7468652d6261646765

