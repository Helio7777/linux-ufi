#!/usr/bin/env bash
set -Eeuo pipefail

# Determine script & repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configurable paths
SRC="${SRC:-$REPO_ROOT}"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/dist}"
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build-tmp}"
MODS_DIR="${MODS_DIR:-$REPO_ROOT/modules-tmp}"

# Determine kernel version from source tree
VERSION=$(make -s -C "$SRC" ARCH=arm64 kernelversion)
LOCALVER="-ufi-stable"
KVER="${VERSION}${LOCALVER}"
PKGVER="${VERSION}-ufi-lzy+stable1"
DTPKG="ufi001c-dtb-${VERSION}-ufi-lzy"
IMAGE_PKG="linux-image-${VERSION}-ufi-lzy"
MODULES_PKG="linux-modules-${KVER}"

# Auto-detect config source
if [ -f "$REPO_ROOT/configs/ufi-${VERSION}-stable.config" ]; then
  CONFIG_SOURCE="$REPO_ROOT/configs/ufi-${VERSION}-stable.config"
elif [ -f "$REPO_ROOT/configs/ufi-7.2.9-stable.config" ]; then
  CONFIG_SOURCE="$REPO_ROOT/configs/ufi-7.2.9-stable.config"
elif [ -f "$REPO_ROOT/configs/ufi-stable.config" ]; then
  CONFIG_SOURCE="$REPO_ROOT/configs/ufi-stable.config"
else
  CONFIG_SOURCE="$(ls -1 "$REPO_ROOT"/configs/ufi-*.config 2>/dev/null | head -n1 || true)"
fi

JOBS="${JOBS:-$(nproc)}"

# Select primary DTB name according to kernel major version
MAJOR_VER="${VERSION%%.*}"
if [ "$MAJOR_VER" = "7" ]; then
  DTB_NAME="msm8916-thwc-ufi001c-nomodem-7.2.dtb"
  DTS_NAME="msm8916-thwc-ufi001c-nomodem-7.2.dts"
else
  DTB_NAME="msm8916-thwc-ufi001c-nomodem-6.12.dtb"
  DTS_NAME="msm8916-thwc-ufi001c-nomodem-6.12.dts"
fi

die(){ echo "ERROR: $*" >&2; exit 1; }

[ -d "$SRC" ] || die "Kernel source directory missing: $SRC"
[ -f "$CONFIG_SOURCE" ] || die "Kernel base config missing: $CONFIG_SOURCE"
command -v aarch64-linux-gnu-gcc >/dev/null || die "missing aarch64-linux-gnu-gcc cross-compiler"
command -v make >/dev/null || die "missing make"
command -v dpkg-deb >/dev/null || die "missing dpkg-deb"

echo "============================================="
echo "Building UFI kernel Debian packages:"
echo "  Base Version:  $VERSION"
echo "  Kernelrelease: $KVER"
echo "  Package Ver:   $PKGVER"
echo "  Base Config:   $CONFIG_SOURCE"
echo "  Target DTB:    $DTB_NAME"
echo "  Parallel Jobs: $JOBS"
echo "  Output Dir:    $OUT_DIR"
echo "============================================="

# 1. Sanity check UFI patches
grep -q 'Invalid 2.4 GHz scan channel' "$SRC/drivers/net/wireless/ath/wcn36xx/txrx.c" ||
  die "WCN3620 channel validation patch missing"
grep -q 'RX survey frequency %d not present in band %d' "$SRC/drivers/net/wireless/ath/wcn36xx/txrx.c" ||
  die "WCN3620 survey validation patch missing"
grep -A2 '^&venus {' "$SRC/arch/arm64/boot/dts/qcom/$DTS_NAME" | grep -q 'status = "disabled"' ||
  die "Venus video codec must remain disabled in DTS"

# 2. Register DTBs in Qualcomm DTS Makefile if absent
if ! grep -q "$DTB_NAME" "$SRC/arch/arm64/boot/dts/qcom/Makefile"; then
  echo "dtb-\$(CONFIG_ARCH_QCOM) += $DTB_NAME" >> "$SRC/arch/arm64/boot/dts/qcom/Makefile"
fi
if [ -f "$SRC/arch/arm64/boot/dts/qcom/msm8916-thwc-ufi001c-nomodem.dts" ] &&
   ! grep -q "msm8916-thwc-ufi001c-nomodem.dtb" "$SRC/arch/arm64/boot/dts/qcom/Makefile"; then
  echo "dtb-\$(CONFIG_ARCH_QCOM) += msm8916-thwc-ufi001c-nomodem.dtb" >> "$SRC/arch/arm64/boot/dts/qcom/Makefile"
fi

rm -rf "$BUILD_DIR" "$MODS_DIR"
mkdir -p "$BUILD_DIR" "$MODS_DIR" "$OUT_DIR"

# 3. Configure .config
cp "$CONFIG_SOURCE" "$BUILD_DIR/.config"
cfg(){ "$SRC/scripts/config" --file "$BUILD_DIR/.config" "$@"; }

export LOCALVERSION=""
cfg --set-str CONFIG_LOCALVERSION "$LOCALVER"
cfg --disable CONFIG_LOCALVERSION_AUTO

# Disable debug symbols, heavy tracing, THP, and unused headless subsystems (essential for 512MB RAM UFI device)
for sym in \
  CONFIG_DEBUG_KERNEL \
  CONFIG_DEBUG_FS \
  CONFIG_DEBUG_MISC \
  CONFIG_DEBUG_MEMORY_INIT \
  CONFIG_DEBUG_BUGVERBOSE \
  CONFIG_DYNAMIC_DEBUG \
  CONFIG_DYNAMIC_DEBUG_CORE \
  CONFIG_MAGIC_SYSRQ \
  CONFIG_LOCKUP_DETECTOR \
  CONFIG_SOFTLOCKUP_DETECTOR \
  CONFIG_SOFTLOCKUP_DETECTOR_INTR_STORM \
  CONFIG_HARDLOCKUP_DETECTOR \
  CONFIG_DETECT_HUNG_TASK \
  CONFIG_WQ_WATCHDOG \
  CONFIG_SCHED_DEBUG \
  CONFIG_SCHEDSTATS \
  CONFIG_RCU_TRACE \
  CONFIG_FTRACE \
  CONFIG_FUNCTION_TRACER \
  CONFIG_FUNCTION_GRAPH_TRACER \
  CONFIG_TRACING \
  CONFIG_UPROBES \
  CONFIG_UPROBE_EVENTS \
  CONFIG_KPROBES \
  CONFIG_KPROBE_EVENTS \
  CONFIG_BPF_EVENTS \
  CONFIG_PSTORE_CONSOLE \
  CONFIG_PSTORE_PMSG \
  CONFIG_PSTORE_FTRACE \
  CONFIG_TRANSPARENT_HUGEPAGE \
  CONFIG_DRM \
  CONFIG_SOUND \
  CONFIG_MEDIA_SUPPORT \
  CONFIG_INPUT_TOUCHSCREEN \
  CONFIG_IIO \
  CONFIG_PINCTRL_IPQ5210 \
  CONFIG_PINCTRL_IPQ5424 \
  CONFIG_PINCTRL_IPQ9650 \
  CONFIG_IPQ_GCC_9650; do
  cfg --disable "$sym"
done

# Ensure UFI required features, hardware crypto acceleration & high availability
cfg --module CONFIG_ZRAM
cfg --enable CONFIG_ZRAM_BACKEND_LZO
cfg --enable CONFIG_ZRAM_BACKEND_LZ4
cfg --enable CONFIG_ZRAM_DEF_COMP_LZORLE
cfg --enable CONFIG_PSTORE
cfg --enable CONFIG_PSTORE_COMPRESS
cfg --enable CONFIG_PSTORE_RAM
cfg --enable CONFIG_WATCHDOG
cfg --enable CONFIG_WATCHDOG_CORE
cfg --enable CONFIG_QCOM_WDT
cfg --enable CONFIG_PM8916_WATCHDOG
cfg --enable CONFIG_PERF_EVENTS
cfg --enable CONFIG_PSI
cfg --set-val CONFIG_PANIC_TIMEOUT 5

# ARMv8-A Crypto Extensions hardware acceleration (AES/SHA for Wi-Fi & network performance)
cfg --enable CONFIG_ARM64_CRYPTO
cfg --enable CONFIG_CRYPTO_AES_ARM64_CE
cfg --enable CONFIG_CRYPTO_SHA1_ARM64_CE
cfg --enable CONFIG_CRYPTO_SHA2_ARM64_CE
cfg --enable CONFIG_CRYPTO_GHASH_ARM64_CE

# TCP BBR congestion control and FQ packet scheduler (built-in for zero-dependency bootup)
cfg --enable CONFIG_TCP_CONG_ADVANCED
cfg --enable CONFIG_TCP_CONG_BBR
cfg --enable CONFIG_NET_SCHED
cfg --enable CONFIG_NET_SCH_FQ

make -C "$SRC" O="$BUILD_DIR" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig

ACTUAL_KVER="$(make -s -C "$SRC" O="$BUILD_DIR" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- kernelrelease)"
[ "$ACTUAL_KVER" = "$KVER" ] || die "unexpected kernelrelease: $ACTUAL_KVER (expected: $KVER)"

# 4. Compile Kernel Image, Modules, and DTBs
echo ">>> Compiling kernel..."
make -C "$SRC" O="$BUILD_DIR" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
  -j"$JOBS" Image modules "qcom/$DTB_NAME" "qcom/msm8916-thwc-ufi001c-nomodem.dtb"

echo ">>> Installing modules to staging..."
make -C "$SRC" O="$BUILD_DIR" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
  modules_install INSTALL_MOD_PATH="$MODS_DIR"

rm -f "$MODS_DIR/lib/modules/$KVER/source" "$MODS_DIR/lib/modules/$KVER/build"

# Verify DTB
if command -v dtc >/dev/null; then
  dtc -I dtb -O dts "$BUILD_DIR/arch/arm64/boot/dts/qcom/$DTB_NAME" 2>/dev/null > "$BUILD_DIR/decoded.dts"
  grep -A12 'video-codec@1d00000' "$BUILD_DIR/decoded.dts" | grep -q 'status = "disabled"' ||
    die "built DTB did not preserve disabled Venus"
fi

# 5. Assemble Debian Packages
echo ">>> Assembling Debian packages..."
WORK_DIR="$BUILD_DIR/deb-staging"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

mkctrl(){
  d="$1"; p="$2"; desc="$3"
  mkdir -p "$d/DEBIAN"
  cat > "$d/DEBIAN/control" <<EOF
Package: $p
Version: $PKGVER
Section: kernel
Priority: optional
Architecture: arm64
Maintainer: UFI Build Automation <actions@github.com>
Description: $desc
 Production UFI001C kernel based on Linux $VERSION.
 Features WCN3620 scan/survey fix, ZRAM LZ4, headless Venus disable,
 and upstream regulatory DB support.
EOF
}

# --- Module Package ---
M="$WORK_DIR/$MODULES_PKG"
mkdir -p "$M"
cp -a "$MODS_DIR/lib" "$M/"
mkctrl "$M" "$MODULES_PKG" "UFI001C Linux modules $KVER"
cat > "$M/DEBIAN/postinst" <<EOF
#!/bin/sh
set -eu
depmod -a $KVER || true
exit 0
EOF
chmod 0755 "$M/DEBIAN/postinst"

# --- DTB Package ---
D="$WORK_DIR/$DTPKG"
mkdir -p "$D/boot/dtbs/qcom"
cp "$BUILD_DIR/arch/arm64/boot/dts/qcom/$DTB_NAME" "$D/boot/dtbs/qcom/$DTB_NAME"
if [ -f "$BUILD_DIR/arch/arm64/boot/dts/qcom/msm8916-thwc-ufi001c-nomodem.dtb" ]; then
  cp "$BUILD_DIR/arch/arm64/boot/dts/qcom/msm8916-thwc-ufi001c-nomodem.dtb" "$D/boot/dtbs/qcom/msm8916-thwc-ufi001c-nomodem.dtb"
fi
mkctrl "$D" "$DTPKG" "UFI001C MSM8916 stable device tree"

# --- Kernel Image Package ---
I="$WORK_DIR/$IMAGE_PKG"
mkdir -p "$I/boot"
cp "$BUILD_DIR/arch/arm64/boot/Image" "$I/boot/Image"
cp "$BUILD_DIR/.config" "$I/boot/config-$KVER"
cp "$BUILD_DIR/System.map" "$I/boot/System.map-$KVER"
mkctrl "$I" "$IMAGE_PKG" "UFI001C Linux stable kernel image $KVER"
sed -i "/^Architecture:/a Depends: $MODULES_PKG (= $PKGVER), $DTPKG (= $PKGVER)" "$I/DEBIAN/control"

cat > "$I/DEBIAN/postinst" <<EOF
#!/bin/sh
set -eu
KVER=$KVER
depmod -a "\$KVER" || true
if command -v update-alternatives >/dev/null 2>&1 &&
   [ -e /lib/firmware/regulatory.db-upstream ]; then
  update-alternatives --set regulatory.db /lib/firmware/regulatory.db-upstream || true
fi
if command -v update-initramfs >/dev/null 2>&1; then
  if [ -e "/boot/initrd.img-\$KVER" ]; then
    update-initramfs -u -k "\$KVER"
  else
    update-initramfs -c -k "\$KVER"
  fi
fi
if [ -x /usr/local/sbin/sync-lkboot ]; then
  /usr/local/sbin/sync-lkboot "\$KVER"
fi
exit 0
EOF
chmod 0755 "$I/DEBIAN/postinst"

# --- Build .deb files ---
echo ">>> Building deb files..."
dpkg-deb --build --root-owner-group "$M" "$OUT_DIR"
dpkg-deb --build --root-owner-group "$D" "$OUT_DIR"
dpkg-deb --build --root-owner-group "$I" "$OUT_DIR"

# Generate SHA256SUMS
(cd "$OUT_DIR" && sha256sum *.deb > SHA256SUMS)

echo "============================================="
echo "Debian packages successfully created in $OUT_DIR:"
ls -lh "$OUT_DIR"/*.deb
cat "$OUT_DIR/SHA256SUMS"
echo "============================================="
