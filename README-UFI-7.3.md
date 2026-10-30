# UFI001C Linux 7.3.y

This branch starts at official Linux stable `v7.3.1` and carries the UFI001C
Wi-Fi-only board support and WCN36xx RX channel/survey validation from the
working 7.2 branch. The modem and Venus video codec remain disabled.

## Build and release

- Maintained branch: `ufi/linux-7.3.y`.
- Upstream tracking branch: `upstream/linux-7.3.y`.
- Configuration seed: `configs/ufi-7.3-stable.config`.
- Build: `bash scripts/build-deb.sh` on Linux with an AArch64 GCC toolchain,
  DTC, initramfs/module packaging dependencies and `dpkg-deb`.
- Device trees: `msm8916-thwc-ufi001c-nomodem-7.3.dtb` and the generic
  `msm8916-thwc-ufi001c-nomodem.dtb` alias.
- Actions: `Kernel Auto Update & Release (7.3.y)`, using
  `.github/workflows/kernel-7.3-update.yml`.

The configuration is resolved by `olddefconfig` against the selected source
version. The build script retains the portable-router settings for BBR/FQ,
WireGuard, CAKE, policy routing, USB NCM/RNDIS and ARM64 crypto support.

The workflow is also installed on the repository default branch so its daily
schedule runs. Manual dispatch accepts `v7.3` or a final `v7.3.x` tag; an empty
tag chooses the latest final release and excludes RC tags. The `v7.3` tag maps
to package/kernel version `7.3.0`.

Successful builds upload three ARM64 Debian packages and `SHA256SUMS`, then
publish Git refs atomically and create/update `ufi-v7.3.x` releases. Existing
release tags are preserved; rebased branch updates use an explicit lease.

The 7.2 workflow and maintained branch continue independently. Build success
does not imply deployment or runtime validation on a physical device.
