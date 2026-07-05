# nextbsd-freebsd-compat

The **FreeBSD base** for NextBSD: a full FreeBSD 15 `buildworld` compiled from
source, minus the toolchain/tests/etc., minus the base tools NextBSD replaces
with its Darwin/Mach stack, minus the paths the Darwin userland overlay owns.
Published as `nextbsd-base-<arch>.tar.gz` and consumed downstream verbatim.

This supplies the FreeBSD-provided half of the OS — `libc`/rtld and the shared
libraries, PAM, `login`/`su`/`passwd`, the POSIX command suites, the UFS/GEOM
family, `pw`, `ldconfig`/`ldd`, etc. The Apple/Darwin half (Mach, launchd,
libdispatch, CoreFoundation, configd, IOKit, kextd, daemons) is built separately
in [`nextbsd-userland`](https://github.com/nextbsd-redux/nextbsd-userland).

## What it builds

A full **`buildworld`** (`.github/workflows/build.yml`), cross-built for both
`amd64` and `arm64` on an x86 runner inside the per-arch
[`nextbsd-kernel-toolchain`](https://github.com/nextbsd-redux/nextbsd-kernel-toolchain)
container. The world is compiled by an **external ports-llvm19** compiler passed
via `--cross-bindir`; the base itself ships **no** compiler (see
[Toolchain](#toolchain)).

`WORLD_FLAGS` trims the world down to what NextBSD ships:

| flag | effect |
|---|---|
| `WITHOUT_TOOLCHAIN=yes` | no base compiler — `cc`/`clang`/`ld.lld` are not built or installed (the external ports-llvm19 clang compiles the world; consumers get clang from ports) |
| `WITHOUT_TESTS=yes` | no `/usr/tests` |
| `WITHOUT_LIB32=yes` | 64-bit only |
| `WITHOUT_DEBUG_FILES=yes` | no split `.debug` |
| `MK_KERBEROS=yes` + krb5/GSSAPI knobs | re-enabled (FreeBSD 15 defaults `MK_KERBEROS=no`); the consumer needs libkrb5/GSSAPI for sshd, curl, git |

A `make.conf` shim bakes rtld's compiled-in default search path
(`/lib:/usr/lib:/usr/lib/system:/System/Library/Libraries:/usr/local/lib`) so
setuid ports/pkg binaries and the GNUstep daemons resolve libraries with no
hints file. Install is `installworld` into `/stage` (never `make distribution`,
so the base carries **no** `/etc` or `/var` content).

## What it strips (and why) — all in this repo

The base is stripped **here**, before the artifact is published — not downstream.
`nextbsd-pkg` repackages the tarball verbatim and does no stripping of its own;
`nextbsd` (ISO) consumes it as-is. Three self-policing stages:

### 1. Superseded base tools — `scripts/strip-superseded.sh` (list: `scripts/superseded`)

FreeBSD base tools NextBSD replaces with a Darwin equivalent from
`nextbsd-userland`. These are **not** path collisions — they are distinct tools
that would be dead/conflicting weight, so the base drops them:

| stripped from base | replaced by (in `nextbsd-userland`) |
|---|---|
| `/sbin/init` | `launchd` (PID 1) |
| `/sbin/kldload` `/sbin/kldstat` `/sbin/kldunload` `/sbin/kldconfig` | `kextload` / `kextstat` / `kextunload` / `kextdeps` |
| `/sbin/devd` `/sbin/devmatch` | `kextd` + libIOKit (IOKit device attach/matching) |
| `/usr/sbin/bsdconfig` `/usr/sbin/bsdinstall` | `nextbsd-installer` |
| `/usr/sbin/freebsd-update` | `pkg` (`NextBSD-*` packages via `nextbsd-pkg`) |
| `libBlocksRuntime.so{,.0}` / `.a` (`/usr/lib`) | Apple's canonical copy in `/usr/lib/system` (base copy shadows it and breaks ObjC — missing `_Block_use_RR2`) |

Every listed path is existence-asserted: a stale entry (base stopped shipping
it) **fails the build** so the list stays honest.

### 2. Base↔userland collisions — `scripts/strip-collisions.sh` (allowlist: `scripts/collisions`)

Paths shipped by **both** the base and the `nextbsd-userland` overlay. pkg
refuses two owners for one path, so the overlay owns the canonical copy and the
base strips it. The set is **derived** (intersect the staged base against
userland's published file list) and checked against the allowlist — any overlap
*not* allow-listed **fails the build**, so a future FreeBSD import or a new Apple
daemon that starts sharing a path stops CI until a human records who wins:

| stripped from base | owned by userland overlay |
|---|---|
| `/usr/sbin/syslogd` | Apple ASL `syslogd` (wired to `com.apple.syslogd.plist`) |
| `/usr/include/Block.h` | Apple Blocks header (libdispatch/CF ABI) |
| `/usr/include/Block_private.h` | Apple private Blocks header |

### 3. Skeleton / kernel — Pack step in `build.yml`

`nextbsd` and its overlays own these, so the base drops the empty skeleton and
asserts they're gone: `/etc`, `/var`, `/root`, `/.profile`, `/.cshrc`, and
`/boot/kernel` (the kernel is `nextbsd-kernel`'s). setuid/setgid bits are
re-applied from the `METALOG` before packing.

## Toolchain

The base ships **no** compiler. `WITHOUT_TOOLCHAIN=yes` gates the cross-tools
clang/lld off, so `/usr/bin/{cc,clang,clang++,cpp}` and `ld.lld` are neither
built nor installed. The world is still compiled — by the **external**
ports-llvm19 toolchain passed via `--cross-bindir` — but nothing from that
compiler lands in the base.

This is deliberate. Gershwin and the other consumers pull `clang` from **ports**
for their own build dependency, so a base compiler would never get used — it only
bloats the ISO and, as the single heaviest compile in `buildworld` (per arch),
dominated the CI cost: shipping base clang/lld pushed the base build from ~20
minutes to ~1h51m for zero downstream benefit. The LLVM/clang version, when the
external toolchain is bumped, is whatever `releng/15.1`'s `contrib/llvm-project`
carries.

If `nextbsd-userland` ever starts shipping its own `clang`/`cc`, the self-policing
`strip-collisions.sh` will fail the build until a `scripts/collisions` entry
records who wins.

## Pipeline

```
nextbsd-kernel-toolchain (fbsd sha) ──toolchain-updated──▶ THIS REPO
  buildworld ▶ installworld ▶ strip (superseded, collisions, skeleton)
  ▶ nextbsd-base-<arch>.tar.gz ─▶ continuous release
        │
        ├─▶ nextbsd-pkg   (repackages verbatim → NextBSD-freebsd-compat pkg)
        └─▶ nextbsd (ISO) (base-updated dispatch, main only)
```

PR builds validate both arches but never cascade (the downstream dispatch is
gated on `refs/heads/main`).

## Related

- Darwin half: [`nextbsd-redux/nextbsd-userland`](https://github.com/nextbsd-redux/nextbsd-userland)
- Packaging (verbatim repackage): [`nextbsd-redux/nextbsd-pkg`](https://github.com/nextbsd-redux/nextbsd-pkg)
- Toolchain image: [`nextbsd-redux/nextbsd-kernel-toolchain`](https://github.com/nextbsd-redux/nextbsd-kernel-toolchain)
- ISO consumer: [`nextbsd-redux/nextbsd`](https://github.com/nextbsd-redux/nextbsd)
- Source build plan: https://pkgdemon.github.io/freebsd-srclist-build-plan.html
