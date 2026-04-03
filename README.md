# netscape304-modern

Launch Netscape Navigator 3.04 for Linux on a modern Linux system without installing old system packages.

This repo does not include the Netscape binary. You must supply:

- `netscape-v304-export_x86-unknown-linux-elf_tar.gz`

Check [WinWorld](https://winworldpc.com/download/98b984dd-c8b4-11ec-b931-0200008a0da4). Put that tarball in the repo root, then run:

```bash
./setup.sh
./run-netscape.sh
```

## What it does

- downloads old Debian `libc5` and X11 runtime packages into `compat/`
- stages classic X bitmap fonts locally under `compat/fonts/`
- builds a small 32-bit preload shim that patches a few startup, DNS, and X11 incompatibilities
- extracts the supplied Netscape tarball into `extracted/`
- launches Netscape with a local state directory under `state/home/`

## Requirements

- Linux with 32-bit x86 execution enabled
- a working X11 display or Xwayland session
- a host 32-bit glibc loader at `/usr/lib32/ld-linux.so.2` or `/usr/lib/ld-linux.so.2`
- `bash`, `curl`, `ar`, `find`, `tar`
- a C compiler with 32-bit build support for `gcc -m32` or equivalent
- `/usr/bin/getent` for the DNS shim
- optional: `xset` to register the bundled bitmap fonts with the X server
  - Common package names: `xorg-xset` on Arch, `x11-xserver-utils` on Debian/Ubuntu, `xset` on Fedora.

## Notes

- This is a compatibility hack, not a period-correct environment.
- Modern HTTPS is still mostly out of scope. Plain HTTP and very simple sites are the realistic target.
- The launcher temporarily adds local `misc`, `75dpi`, and `100dpi` bitmap font paths before starting Netscape and removes them again on exit.

## Compatibility proxies

If you want to reach more of the modern web, run a compatibility proxy on another machine or locally and point Netscape at it as an HTTP proxy.

- WebOne: <https://github.com/atauenis/webone>
- WRP (Web Rendering Proxy): <https://github.com/tenox7/wrp>

## Debugging

DNS shim logging:

```bash
NETSCAPE_SHIM_DEBUG=1 ./run-netscape.sh
```

Keep Netscape subprocess messages on the terminal:

```bash
NETSCAPE_STDIO_TO_TERMINAL=1 NETSCAPE_SHIM_DEBUG=1 ./run-netscape.sh
```
