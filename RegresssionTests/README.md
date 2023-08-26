# P2-FLASH-FS / RegresssionTests
These are unit/regression test files that I'm using to certify the FS operation with each release.

![Project Maintenance][maintenance-shield]

[![License][license-shield]](LICENSE)


## The test files 

This is a recap of the version history of these files:

| Date | Status |
| --- | --- |
|  <PRE>2023-Aug-26</PRE> | Initial release.	Working Format, Mount, open(file, "R"), open(file, "W"), close(), wr\_byte(), rd\_byte(), wr\_word(), rd\_word(), wr\_long(), rd\_long(), wr\_str(), and rd\_str() |



## Test Files by Stephen

This is my work in progress as I'm working toward customer facing release of the FileSystem code


| File | Purpose |
| --- | --- |
| [UT\_utilities.spin2](UT_utilities.spin2) | Utility methods common to all Test Files |
| [UT\_read\_write_tests.spin2](UT_read_write_tests.spin2) | The read/write basic types test suite - more testing to be awakened in it! |
| [UT\_read\_write_tests.log](UT_read_write_tests.log) | Log of the read/write basic types tests |

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

