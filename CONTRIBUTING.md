# P2-FLASH-FS - How to contribute code you write
Flash FS - a filesystem for the FLASH chip on the P2 Edge Module.

![Project Maintenance][maintenance-shield]

[![License][license-shield]](LICENSE)

## Table of Contents

On this Page:

- [Contributing](#contributing) - why your help is welcome
- [How to make a clean pull request](#how-to-make-a-clean-pull-request) - the steps, from fork to merge
- [Running the regression tests](#running-the-regression-tests) - the runner, its options and the debug routing
- [How to Contribute](#how-to-contribute) - file an issue, or send a pull request

Additional pages:

- [README](README.md) - the top page, with every page by topic
- [Regression Tests](RegresssionTests/README.md) - the test programs and their results
- [Test Coverage](RegresssionTests/COVERAGE.md) - which program checks which method and behavior
- [CHANGELOG](CHANGELOG.md) - the release history

Contributing
============
If you want to contribute to our project and make it better, your help is very welcome. Contributing is also a great way to learn more about social coding on GitHub, new technologies and their ecosystems and how to make constructive, helpful bug reports, feature requests and the noblest of all contributions: a good, clean pull request.

### How to make a clean pull request

- Create a personal fork of this project on GitHub.
- Clone the fork on your local machine. Your remote repo on GitHub is called `origin`.
- Add the original repository as a remote called `upstream`.
- If you created your fork a while ago be sure to pull upstream changes into your local repository.
- Create a new branch to work on! Branch from `main`.
- Implement/fix your feature, comment your code.
- Follow the code style of the project, including indentation.
- Build the driver and the demo with **pnut-ts**: `pnut-ts flash_fs.spin2 && pnut-ts -d flash_fs_demo.spin2`. Both should compile with no warnings.
- Run the regression tests (see [Running the regression tests](#running-the-regression-tests)): `tools/run_tests.sh` compiles every program in **RegresssionTests/**, and on a Mac with a P2 Edge attached it also downloads and runs each one, capturing its log. `tools/run_tests.sh --help` shows the options.
- Write or adapt tests as needed.
- Add or change the documentation as needed.
- Squash your commits into a single commit with git's [interactive rebase](https://help.github.com/articles/interactive-rebase). Create a new branch if necessary.
- Push your branch to your fork on GitHub, the remote `origin`.
- From your fork open a pull request against the project's `main` branch.
- If the maintainer requests further changes just push them to your branch. The PR will be updated automatically.
- Once the pull request is approved and merged you can pull the changes from `upstream` to your local repo and delete your extra branch(es).

And last but not least: Always write your commit messages in the present tense. Your commit message should describe what the commit, when applied, does to the code, not what you did to the code.

### Running the regression tests

The programs call the driver's `TEST_` methods, which sit below the `REMOVE BEFORE FLIGHT` line at the end of `flash_fs.spin2`. The shipped driver has that block commented out, and the runner never edits it: **tools/run_tests.sh** writes a hook-enabled copy of the driver to `RegresssionTests/build/flash_fs.spin2` (the one line containing `REMOVE BEFORE FLIGHT` gets its leading `{` changed to `'{`), compiles each program against that copy with **pnut-ts**, and on the macOS host downloads and runs each one with **pnut-term-ts**, then judges its log. The repository's own `flash_fs.spin2` is only ever read.

```bash
# compile every program, do not run anything (the default off the macOS host)
tools/run_tests.sh --compile-only

# compile, download, run and judge every program (the default on the macOS host)
tools/run_tests.sh --run

# one program only
tools/run_tests.sh --run RT_rmw_extended_tests

# run the suite with a driver built another way (replaces the default value of a CON constant)
tools/run_tests.sh --run --set HANDLE_BASE=1
tools/run_tests.sh --run --set MAX_FILES_OPEN=1 RT_single_handle_smoke_tests

# judge a log you already have, compiling and running nothing
tools/run_tests.sh --judge RegresssionTests/RT_rmw_extended_tests.log
```

| Option | What it does |
| --- | --- |
| `--compile-only` / `--run` | compile only, or compile, download, run and capture |
| `--set NAME=VALUE` | replace the default value of the CON constant NAME in the generated driver copy |
| `--define SYMBOL` | define a preprocessor symbol for every program (for example `FULL_FLASH_GUARD_ONLY`) |
| `--timeout SECONDS` | per-program run timeout (default 600) |
| `--driver FILE` | test this driver file instead of the repository's `flash_fs.spin2` |
| `--judge LOGFILE` | judge an existing log and compile nothing |

The runner prints one line per program: `PASS`, `FAIL`, `UNKNOWN` (no usable summary in the log) or, in compile-only mode, `COMPILED`; and a `TOTAL` line. It exits 0 when every program passed or compiled. A program passes when its log carries a `RESULT: PASS` line with equal counts. A plain run writes the log to `RegresssionTests/<program>.log`, replacing the tracked log; a run with `--set` or `--define` writes under `RegresssionTests/build/` so a tracked log is only replaced by a plain run. `tools/run_tests.sh --help` lists everything.

Running a program needs a P2 Edge on a serial port of the computer. `--compile-only` needs none and checks only that every program compiles against the driver. The [Regression Tests](RegresssionTests/README.md) page lists every program and its result, and [Test Coverage](RegresssionTests/COVERAGE.md) says which program checks which method.

#### Determine debug output routing (RT_*.spin2 files)

At the head of each of the RT .spin2 test files you want to run look for the debug output lines:

```spin2
{
    ' debug via serial to RPi (using RPi gateway pins)
    DEBUG_PIN_TX = 57           ' GRY GPIO 10
    DEBUG_PIN_RX = 56           ' WHT GPIO 8 (gnd is BLK GPIO 6)
    DEBUG_WINDOWS_OFF = -1      ' no debug windows showing
    DEBUG_BAUD = 2_000_000      ' comms at 2Mbit
'}
```

These lines when uncommented route the debug serial to PINs 56/57 which I connect to the Raspberry Pi for logging as there is a lot of output from the test runs.

In their present form (commented out) the debug output just goes to the debug window where you are running the compiler.

We're excited to see what changes you would like to contribute!

*(Special Thanks to [Marc Diethelm](https://github.com/MarcDiethelm) for this initial content for this page.)*

## How to Contribute

This is a project supporting our P2 Development Community. Please feel free to contribute to this project. You can contribute in the following ways:

- File **Feature Requests** or **Issues** (describing things you are seeing while using our code) at the [Project Issue Tracking Page](https://github.com/ironsheep/P2-FLASH-FS/issues)
- Fork this repo and then add your code to it. Finally, create a Pull Request to contribute your code back to this repository for inclusion with the projects code. See [CONTRIBUTING](CONTRIBUTING.md)

---

> If you like my work and/or this has helped you in some way then feel free to help me out for a couple of :coffee:'s or :pizza: slices!
>
> [![coffee](https://www.buymeacoffee.com/assets/img/custom_images/black_img.png)](https://www.buymeacoffee.com/ironsheep) &nbsp;&nbsp; -OR- &nbsp;&nbsp; [![Patreon](./DOCs/images/patreon.png)](https://www.patreon.com/IronSheep?fan_landing=true)[Patreon.com/IronSheep](https://www.patreon.com/IronSheep?fan_landing=true)

---

## Disclaimer and Legal

> *Parallax, Propeller Spin, and the Parallax and Propeller Hat logos* are trademarks of Parallax Inc., dba Parallax Semiconductor
>
> This project is in no way affiliated with, authorized, maintained, sponsored or endorsed by *Parallax Inc., dba Parallax Semiconductor* or any of its affiliates or subsidiaries.

---

## License

Licensed under the MIT License.

Follow these links for more information:

### [Copyright](copyright) | [License](LICENSE)

[maintenance-shield]: https://img.shields.io/badge/maintainer-stephen%40ironsheep%2ebiz-blue.svg?style=for-the-badge

[license-shield]: https://img.shields.io/badge/License-MIT-yellow.svg
