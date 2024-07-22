# update-petitboot.sh

The [`update-petitboot.sh`](update-petitboot.sh) scripts generates a
`petitboot.conf` file from the files in the `/boot` directory.

## Usage

Install the `update-petitboot.sh` script to your system
(e.g. to `/boot/update-petitboot.sh`) and then run it after every kernel update
to regenerate the menu entries.

## Configuration

The `update-petitboot.sh` script can be configured using a
`/boot/update-petitboot.conf` file.
This file will be sourced by the script, so it has to conform to POSIX shell
syntax.

In it, you can set these variables:

#### `os_name` *(default: `Linux`)*
The prefix for all menu entries.

#### `append` *(default: none)*
Kernel cmdline arguments (default: none).

#### `consoles` *(default: `tty`)*
The consoles the system has to boot.

On OpenPOWER systems this is usually the serial console (`hvc0`) and the
framebuffer (`tty`).

If you prefer a "nicer" label than the device name you can use the
`[label=]dev` syntax, e.g. `VGA=tty` or `serial=hvc0`.
