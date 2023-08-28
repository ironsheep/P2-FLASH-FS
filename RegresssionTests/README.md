# P2-FLASH-FS / RegresssionTests
These are unit/regression test files that I'm using to certify the FS operation with each release.

![Project Maintenance][maintenance-shield]

[![License][license-shield]](LICENSE)

## Running the tests

In order the compile the tests you need to uncomment the test-support routines in `Draft_flash_fs.spin2`. Look for line 1705:

#### Driver file: Draft\_flash\_fs.spin2: line 1705
```spin2
{   ' REMOVE BEFORE FLIGHT: uncomment this line before release!!!

' ----------------------------------------------------------------------------------------------
'   these methods are for regression testing only - they are not used in production code
```
comment out the 1st line to enable the code that follows. [ place a ' before the {... ]


#### Determine debug output routing (UT_*.spin2 files)

At the head of each of test UT .spin2 files you want to run look for the debug output lines:

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


## The test files 

This is a recap of the version history of these files:

| Date | Status |
| --- | --- |
|  <PRE>2023-Aug-26</PRE> | Initial release. `UT_read_write_tests.spin2`<br>Working Format, Mount, open(file, "R"), open(file, "W"), close(),<br>Focused tests for wr\_byte(), rd\_byte(), wr\_word(), rd\_word(), wr\_long(), rd\_long(), wr\_str(), and rd\_str() <br>Spanning blocks tests need to be added|
|  <PRE>2023-Aug-27</PRE> | More Tests: `UT_read_write_block_tests.spin2`<br>Working Format, Mount, open(file, "R"), open(file, "W"), close(),<br>Focused tests for read(), write(), and file\_size_unused(): in only block, spanning two blocks, spanning 3 blocks |




## Test Files by Stephen

This is my work in progress as I'm working toward customer facing release of the FileSystem code


| File | Purpose |
| --- | --- |
| [UT\_utilities.spin2](UT_utilities.spin2) | Utility methods common to all Test Files |
| [UT\_read\_write_tests.spin2](UT_read_write_tests.spin2) | The read/write basic types test suite - more testing to be awakened in it! |
| [UT\_read\_write_tests.log](UT_read_write_tests.log) | Log of the read/write basic types tests [45 passes, 0 fails] |
| [UT\_read\_write\_block_tests.spin2](UT_read_write_block_tests.spin2) | The read/write records(blocks) test suite  |
| [UT\_read\_write\_block_tests.log](UT_read_write_block_tests.log) | Log of the read/write records(blocks) tests  [39 passes, 0 fails]<br>(*42 successes (+3) were extra checks I did for 3 tests*) |

### Next Steps:

- Add many more tests!
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

