# Building the RootHide .deb on Linux

The package is built with [Theos](https://theos.dev) using the
[`roothide/theos`](https://github.com/roothide/theos) fork so that

- `THEOS_PACKAGE_SCHEME=roothide` applies RootHide packaging rules (the fork
  also forces `Architecture: iphoneos-arm64e`), and
- `make package` stages a **rootful-style payload** (`Applications/`, `usr/…`),
  which RootHide's dpkg relocates into its randomized jailbreak root.

## One-time setup

```sh
git clone --depth 1 --recurse-submodules https://github.com/roothide/theos ~/theos

# iOS toolchain (clang + ldid) for Linux:
curl -fsSL "https://github.com/L1ghtmann/llvm-project/releases/latest/download/iOSToolchain-$(uname -m).tar.xz" \
  | tar -xJf - -C ~/theos/toolchain/
test -x ~/theos/toolchain/linux/iphone/bin/clang

# iOS SDK (iPhoneOS16.5 at time of writing):
THEOS=~/theos ~/theos/bin/install-sdk latest
```

Host requirements: `git make perl rsync fakeroot python3 curl xz` (the GitHub
Actions workflow installs them with `apt-get`).

## Build

```sh
THEOS=~/theos npm run build:deb
```

which runs:

```sh
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
```

and verifies + emits `dist/<Package>_<Version>_iphoneos-arm64e.deb`.

## Notes

### `plistutil` shim

Theos converts the app's XML `Info.plist` to binary form with a converter found
on `PATH`. The Linux toolchain ships a `plistutil` that links against
`libplist-2.0.so.4`, which most runners do not have. `scripts/plistutil` is a
small Python (`plistlib`) drop-in implementing exactly the flags Theos calls
(`-i -f bin -o`); `scripts/build.mjs` puts `scripts/` first on `PATH`, so
neither local builds nor CI need `libplist-utils`.

### Entitlements

The app binary is signed with `native/entitlements.plist`
(`platform-application`, `no-container`, `skip-library-validation`) via
`ldid -S`, mirroring what NewTerm ships; verify with
`ldid -e TerminalIPHONE`.

### arm64e linkage warning

`ld` may print `object file … was built with an incompatible arm64e ABI
compiler`. That combination (L1ghtmann's llvm-project toolchain + its ld) is
exactly what `roothide/theos`' own installer ships for Linux, so it is expected
on this path; the produced binary reports `Mach-O 64-bit arm64e`.

### Runtime path resolution

Nothing under `/var/jb` is hardcoded anywhere: the app derives the jailbreak
root from its own executable path (`<root>/Applications/TerminalIPHONE.app/…`),
`layout/usr/bin/terminal-iphone` derives it from `dirname "$0"`, and `postinst`
derives it from the location of `apt-get`/`uicache`/`dpkg`. System paths
(`/var/mobile`, `/tmp`) are scheme-independent and used directly.