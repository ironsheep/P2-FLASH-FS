# P2-FLASH-FS
The future home of our Flash FS a filesystem for the FLASH chip on the P2 Edge Module.

![Project Maintenance][maintenance-shield]

[![License][license-shield]](LICENSE)

## Table of Contents

On this Page:

- [Flash Filesystem Features](#flash-filesystem-features) - key features of this filesystem / design goals
- [Contributing](#how-to-contribute) - you can contribute to this project

Additional pages:

- [SPI FLASH Datasheet](./DOCs/W25Q128JV-210823.pdf) - our FLASH Chip Datasheet
- [FS Theory of Operations](THEOPS.md) - a deteailed descript of how this filesystem works

## Flash Filesystem Features

- Wear-leveling write mechanism
- Writes are stuctured to facilitate recovery  of file structure after unplanned power failure
- Can be accessed from all cogs (first cog to call mount() mounts the filesystem for all cogs to use.)

## How to Contribute

This is a project supporting our P2 Development Community. Please feel free to contribute to this project. You can contribute in the following ways:

- File **Feature Requests** or **Issues** (describing things you are seeing while using our code) at the [Project Issue Tracking Page](https://github.com/ironsheep/P2-FLASH-FS/issues)
- Fork this repo and then add your code to it. Finally, create a Pull Request to contribute your code back to this repository for inclusion with the projects code. See [CONTRIBUTING](CONTRIBUTING.md)

## Credits

Thank you to **Chip Gracy** for the excellent **FLash File System 16MB** written for the P2 which is the core of this fileysystem.

Thank you to **Jon McPhalen** for helping to specify the customer facing API for this filesystem and for guidance in our future directions for the upcoming dual filesystem driver as well.

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

Copyright © 2023 Iron Sheep Productions, LLC. All rights reserved.

Licensed under the MIT License.

Follow these links for more information:

### [Copyright](copyright) | [License](LICENSE)

[maintenance-shield]: https://img.shields.io/badge/maintainer-stephen%40ironsheep%2ebiz-blue.svg?style=for-the-badge

[license-shield]: https://camo.githubusercontent.com/bc04f96d911ea5f6e3b00e44fc0731ea74c8e1e9/68747470733a2f2f696d672e736869656c64732e696f2f6769746875622f6c6963656e73652f69616e74726963682f746578742d646976696465722d726f772e7376673f7374796c653d666f722d7468652d6261646765
