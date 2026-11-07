# patches/

World source patches applied on top of the toolchain image's baked
`/usr/src` (a shallow `git clone` of `nextbsd/freebsd-src` `releng/15.1`),
with `git apply`, in the order listed in [`series`](series). The same layout
as [`nextbsd-kernel/patches`](https://github.com/nextbsd/nextbsd-kernel/tree/main/patches).

The "Apply NextBSD source patches" step in
[`build.yml`](../.github/workflows/build.yml) runs before buildworld. It logs
each patch, and the build fails on the first patch that does not apply.

## `series` format

One patch filename per line, relative to this directory. **No comments or
blank lines**: the step applies the file verbatim with

```sh
for p in $(cat patches/series); do git apply patches/$p; done
```

so anything in `series` is treated as a filename. Keep it to real patch names.

## Adding a patch

```sh
cd /usr/src                  # a nextbsd/freebsd-src releng/15.1 checkout,
                             # at the SHA the toolchain image bakes
# ... edit files, commit ...
git format-patch -1 -o /path/to/nextbsd-freebsd-compat/patches/
echo "0006-NextBSD-my-change.patch" >> /path/to/nextbsd-freebsd-compat/patches/series
```

Name NextBSD-authored patches `00NN-NextBSD-<summary>.patch` and start the
subject with `NextBSD:`. Say in the commit message why NextBSD carries the
patch, and end it with `Carried out-of-tree for NextBSD.`

A PR that touches `patches/**` builds world on both arches. Re-check every
patch when the base branch moves: they are carried, not owned.

## Current series: `__FreeBSD_version` 2700000

NextBSD's kernel moves to `__FreeBSD_version` 2700000 (NextBSD 27.0.0,
still on the releng/15.1 API; nextbsd/nextbsd-kernel#376). Upstream code in
the releng/15.1 tree that compares `__FreeBSD_version` against 16.x values
would then take the 16.x path against 15.1 headers. A full-tree audit found
these world sites; each patch keeps the releng/15.1 behaviour unconditionally.
At today's 1501000 every patch is a no-op: it keeps the code that is compiled
now.

| patch | site | effect |
|---|---|---|
| `0001` | `lib/csu/common/crtbrand.S` | ABI note is `__FreeBSD_version` again, not the `1501000` that upstream 96841ea08d hard-coded, so every binary's note follows `param.h` |
| `0002` | `sys/contrib/openzfs/module/nvpair/nvpair.c` | drops the `>= 1600010` clause: keeps the variadic releng/15.1 `xdrproc_t` callbacks |
| `0003` | `sbin/devd/devd.cc` | keeps the releng/15.1 `system="kern"` error, not `#error "Remove this gross hack"` |
| `0004` | `usr.sbin/ctladm/ctladm.c` | keeps `ctladm port -l/-q/-x` |
| `0005` | `sys/sys/efiio.h` | keeps `efi_get_table_ioc`/`efi_waketime_ioc` for `efitable` and `efiwake` |

## `0006`: public libzstd

releng/15.1 builds `lib/libzstd` as a `PRIVATELIB` (`libprivatezstd.so.5`,
headers in `/usr/include/private/zstd`, no `.pc`). NextBSD has no ports, so
programs built for it need base's zstd as an ordinary library
(nextbsd/nextbsd#611). `0006` installs it under zstd's own SONAME,
`libzstd.so.1`, with `zstd.h`, `zstd_errors.h`, `zdict.h` in `/usr/include`
and `libzstd.pc` (version read from `zstd.h`) in `/usr/libdata/pkgconfig`.
`share/mk` moves zstd from `_PRIVATELIBS` to `_LIBRARIES`, so every
`LIBADD= zstd` consumer (zstd(1), libarchive, gzip, mkuzip, savecore, the
clang programs) links `-lzstd`; rescue and `tools/bsdbox` use `-lzstd`, and
`ObsoleteFiles.inc` lists the old `libprivatezstd` files. "Inspect /stage"
prints the library, headers, `.pc` and `zstd`'s `NEEDED` entries.

## `0007`: swapon(8) swaps on a local file without md(4)

NextBSD's kernel accepts `swapon(2)` on a regular file on UFS and pages to
its blocks through a pinned extent map (nextbsd/nextbsd-kernel#214), so a
swap file no longer needs an `md(4)` vnode device, whose kthread can
deadlock in `VOP_WRITE` under memory pressure. `0007` makes
`swapon /private/var/vm/swapfile0` call `swapon(2)` on the file, and an
fstab `md none swap sw,file=/path` entry swap on the file itself. Only
`ENOTBLK` (a kernel without #214, or a filesystem other than UFS, such as
ZFS) falls back: the fstab `md` form attaches `md(4)` as before, and a
plain file path fails with a message saying the kernel cannot swap on it.
`md.eli` entries keep `md(4)` for `geli(8)`. `swapctl -l`/`swapinfo` show a
swap file as `[file]`.

## `0008`: dumpon(8)/savecore(8) on a regular file

NextBSD's kernel can write a crash dump to a preallocated regular file on
UFS, such as `/private/var/vm/kernelcore`, through the file's pinned extent
map (nextbsd/nextbsd-kernel#216). `0008` makes `dumpon /path/to/file`
configure it: an absolute path outside `/dev` is opened as is and
`DIOCSKERNELDUMP` goes to the kernel's file dumper. `savecore` reads a
regular file as a dump medium with 4096-byte sectors and keeps absolute
paths without a `/dev/` prefix. A configured dump file cannot be written,
so savecore cannot clear its header while it is configured; savecore says
to run it before `dumpon`, or after `dumpon -r`. On a kernel without the
file dumper, dumpon says the kernel cannot dump to a regular file; on ZFS
the kernel refuses the file. Devices and netdump are unchanged.

## `0009`: virtual_oss Bluetooth backend

releng/15.1's `lib/virtual_oss` builds only the `null` and `oss` backends,
so `voss_bt.so` was missing: `virtual_oss -P /dev/bluetooth/<addr>` exited,
and `virtual_bt_speaker` exited at startup because it dlsyms its AVDTP
acceptor from that file (nextbsd/nextbsd#485). `0009` builds `bt` when
`MK_BLUETOOTH` is on, installing `/usr/lib/virtual_oss/voss_bt.so` (SBC
only; no `HAVE_LIBAV`, so no AAC or ffmpeg). `Makefile.inc1` adds
`lib/libbluetooth` and `lib/libsdp`, which it links, to `_prebuild_libs`,
because buildworld builds all of `lib/` before installing any of it into
the sysroot. `virtual_oss` loads the `bt` backend from `/usr` instead of `/usr/local`.

## `0010`: no FreeBSD Bluetooth daemons or tools

`bluetoothd` and `bluetooth(8)` from `nextbsd-userland` are NextBSD's only
Bluetooth userland (E16, nextbsd/nextbsd#473): they do controller setup,
pairing, SDP, HID, firmware download and the A2DP sink. `0010` stops world
building the FreeBSD programs that did those jobs, so they never reach the
stage: `usr.sbin/bluetooth` (`hcsecd`, `sdpd`, `bthidd`, `bthidcontrol`,
`iwmbtfw`, `rtlbtfw`, `ath3kfw`, `bcmfw`, `hccontrol`, `l2control`, `l2ping`,
`sdpcontrol`, `btpand`, `rfcomm_pppd`, `bluetooth-config`), `usr.bin/bluetooth`
(`bthost`, `btsockstat`, `rfcomm_sppd`), `virtual_bt_speaker`, and the
Bluetooth rc.d scripts. Their man pages and their `/etc/bluetooth`,
`/etc/defaults` and `/etc/devd` configuration go with them. `MK_BLUETOOTH`
stays on, so `libbluetooth`, `libsdp`, `ng_bluetooth(4)`, the netgraph
Bluetooth headers and `0009`'s `voss_bt.so` are still built.

## `0011`: loader boot-video mode

The first loader patch for NextBSD's graphical boot (nextbsd/nextbsd#542,
nextbsd/nextbsd-freebsd-compat#77). `loader.efi` takes on boot.efi's role
and decides xnu's `Boot_Video` `v_display` once, in `main()` before the
console is probed:

- **graphics** (`GRAPHICS_MODE`, 1) when ConOut lists no serial port, the
  load options have none of `-v`, `-s`, `-a`, `-h`, `-D`, and there is a
  GOP framebuffer;
- **text** (`FB_TEXT_MODE`, 2) otherwise: the stock loader, unchanged.

In graphics mode no loader text reaches the screen. `efi_cons_putchar()`
keeps it in a 16 KB replay ring and teken draws nothing, so the screen
belongs to the boot splash; comconsole output is never kept. The loader
drops to text and replays the ring when the boot flags or `loader.conf`
ask for verbose, single-user or a serial console (`boot_verbose`,
`boot_single`, `boot_askname`, `boot_serial`, `boot_multicons`, or
`comconsole` in `console`), when something must wait for the user (the
beastie menu, a password or GELI prompt), and on every error path: the
`OK` prompt after a failed boot, `interactive_interrupt()` and a loader
panic. No key leaves graphics mode, as on Darwin, so autoboot boots at
once in that mode. `boot-video [status | is-graphics | text]` reports
or changes the mode.

CI's OVMF/AAVMF list the UART in ConOut (the loader prints
`Console: efi (0x20000000)`, `RB_MULTIPLE`), so CI stays in text mode and
its serial output is unchanged.

## `0012`: exact-RGB fill; no GOP SetMode to the same mode

Primitives for the boot splash (nextbsd/nextbsd-freebsd-compat#78).
`gfx.fb_fill_rgb(r, g, b [, x1, y1, x2, y2])` fills the framebuffer, or a
rectangle clipped to it, with an exact colour as one GOP `VideoFill`.
`gfx.fb_drawrect` only paints the 16-colour teken palette, and scaling a
PNG to full screen needs about 33 MB of loader heap at 4K; the fill
allocates nothing. `gop_autoresize()` (`efi-autoresizecons`) no longer
calls `SetMode()` when the best mode is already the current one, because
`SetMode()` clears the screen to black even then.
