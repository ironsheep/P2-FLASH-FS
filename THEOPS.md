# P2 FLASH Filesystem - Theory of Operations

THis page presents the theory behind our Flash FS a filesystem for the FLASH chip on the P2 Edge Module.

![Project Maintenance][maintenance-shield]

[![License][license-shield]](LICENSE)

## Table of Contents

On this Page:

- ...

Additional pages:

- [SPI FLASH Datasheet](./DOCs/W25Q128JV-210823.pdf) - our FLASH Chip Datasheet
- [Top README](https://github.com/ironsheep/P2-FLASH-FS) - back to the top page of this project


## Initial build

Key Constants in the file describe:

- **SPI_[CS|CK|DI|DO]** - The signal lines used for the SPI flash chip
- **FIRST_BLOCK** - The starting block to be used within the Flash chip.  By default the value is chosen to allow for the first 512KB to be resorced the boot loaded code for the P2.
- **LAST_BLOCK** - The address of the last block to be allocated to the filesystem. This effectivly tells us the amount of space whihc is allocated to this filesystem
- **MAX_FILES_OPEN** - a 4k buffer is allocated to each file we could have open at the same time as another. This defaults to 2 so we can at least copy one file to another.
- **BLOCK_SIZE** - fixed at 4KB, this is the smallest eraseable amount of space within the SPI FLASH chip we use.

*Most users will not need to adjust these values!*

**NOTE**: *The SPI signal lines are shared with the uSD socket on P2 Edge Modules that have a uSD socket.*

## Concepts

Block IDs - blocks have IDs that are sequentially allocated and reused when associated blocks are freed.

Block Placement - to aid in wear leveling all 4k block locations are randomly chosen



## Tracking Data

## The Mount Process (m)

Upon Mount the entire flash space is scanned for well-formed blocks and work is completed if found incomplete. Lastly any badly formed blocks/block chains are freed. In this last case an error code is returned from mount

### (m1) Initial scan
### (m2) Completing work which didn't complete due to power fail

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

Copyright © 2022 Iron Sheep Productions, LLC. All rights reserved.

Licensed under the MIT License.

Follow these links for more information:

### [Copyright](copyright) | [License](LICENSE)

[maintenance-shield]: https://img.shields.io/badge/maintainer-stephen%40ironsheep%2ebiz-blue.svg?style=for-the-badge

[license-shield]: https://camo.githubusercontent.com/bc04f96d911ea5f6e3b00e44fc0731ea74c8e1e9/68747470733a2f2f696d672e736869656c64732e696f2f6769746875622f6c6963656e73652f69616e74726963682f746578742d646976696465722d726f772e7376673f7374796c653d666f722d7468652d6261646765
