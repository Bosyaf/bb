#!/bin/bash
set -Eeuo pipefail

# Configuration
KERNEL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN="$(dirname "$KERNEL_DIR")"
KERNEL_DEFCONFIG="shen_gki_defconfig"
CLANG_DIR="$MAIN/toolchains/clang-1"
OUT_DIR="$KERNEL_DIR/out"
ZIMAGE_DIR="$OUT_DIR/arch/arm64/boot"
DTB_DTBO_DIR="$ZIMAGE_DIR/dts/vendor/qcom"
BUILD_START=$(date +%s)

export ARCH=arm64
export SUBARCH=arm64
export BOARD_PLATFORM=pineapple
export DEVNAME=kiwi_v2
export MODNAME=qca_cld3_kiwi_v2
export DYNAMIC_SINGLE_CHIP=kiwi_v2
export WLAN_CTRL_NAME=wlan
export WLAN_PROFILE=kiwi_v2

export AUDIO_ROOT="$KERNEL_DIR/techpack/audio-kernel"
export CAMERA_ROOT="$KERNEL_DIR/techpack/camera-kernel"
export DISPLAY_ROOT="$KERNEL_DIR/techpack/display-drivers"
export GRAPHICS_ROOT="$KERNEL_DIR/techpack/graphics-kernel"
export MM_ROOT="$KERNEL_DIR/techpack/mm-drivers"
export MMRM_ROOT="$KERNEL_DIR/techpack/mmrm-driver"
export SECUREMSM_ROOT="$KERNEL_DIR/techpack/securemsm-kernel"
export SYNX_ROOT="$KERNEL_DIR/techpack/synx-kernel"
export TOUCH_ROOT="$KERNEL_DIR/techpack/touch-drivers"
export WLAN_ROOT="$KERNEL_DIR/techpack/wlan"

# Clang: kalici kurulum
# Android prebuilts içindeki Linux x86_64 derleyicisi
CLANG_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/android14-security-release/clang-r487747c.tar.gz"

if [ ! -x "$CLANG_DIR/bin/clang" ]; then
    echo "Clang kurulumu eksik; indiriliyor..."
    mkdir -p "$CLANG_DIR"
    TMP_ARCHIVE="$MAIN/clang.tar.gz"
    wget -O "$TMP_ARCHIVE" "$CLANG_URL"
    tar -xzf "$TMP_ARCHIVE" -C "$CLANG_DIR"
    rm -f "$TMP_ARCHIVE"
fi

if [ ! -x "$CLANG_DIR/bin/clang" ]; then
    echo "HATA: Clang bulunamadi: $CLANG_DIR/bin/clang"
    exit 1
fi

export PATH="$CLANG_DIR/bin:$PATH"
export CC="$CLANG_DIR/bin/clang"
export CXX="$CLANG_DIR/bin/clang++"
export HOSTCC="$CLANG_DIR/bin/clang"
export HOSTCXX="$CLANG_DIR/bin/clang++"
export LD="$CLANG_DIR/bin/ld.lld"
export AR="$CLANG_DIR/bin/llvm-ar"
export NM="$CLANG_DIR/bin/llvm-nm"
export STRIP="$CLANG_DIR/bin/llvm-strip"
export OBJCOPY="$CLANG_DIR/bin/llvm-objcopy"
export OBJDUMP="$CLANG_DIR/bin/llvm-objdump"
export HOSTAR="$CLANG_DIR/bin/llvm-ar"
export HOSTLD="$CLANG_DIR/bin/ld.lld"
export LLVM=1
export LLVM_IAS=1
export CROSS_COMPILE=aarch64-linux-gnu-
export KBUILD_COMPILER_STRING="$("$CC" --version | head -n 1)"

echo "Kullanilan Clang: $KBUILD_COMPILER_STRING"
echo "Kernel source: $KERNEL_DIR"
echo "Output: $OUT_DIR"

# Include paths
INCLUDE_PATHS=(
    "-I$KERNEL_DIR/include"
    "-I$KERNEL_DIR/arch/arm64/include"
    "-I$KERNEL_DIR/drivers/base/regmap"
    "-I$AUDIO_ROOT/include"
    "-I$CAMERA_ROOT/include"
    "-I$DISPLAY_ROOT/include"
    "-I$GRAPHICS_ROOT/include"
)

# YYLLOC workaround
echo "Applying YYLLOC workaround..."
YYLL1="$KERNEL_DIR/scripts/dtc/dtc-lexer.lex.c_shipped"
YYLL2="$KERNEL_DIR/scripts/dtc/dtc-lexer.l"

[ ! -f "$YYLL1" ] || sed -i 's/extern YYLTYPE yylloc/YYLTYPE yylloc/g;s/YYLTYPE yylloc/extern YYLTYPE yylloc/g' "$YYLL1"
[ ! -f "$YYLL2" ] || sed -i 's/extern YYLTYPE yylloc/YYLTYPE yylloc/g;s/YYLTYPE yylloc/extern YYLTYPE yylloc/g' "$YYLL2"

# Optional clean build: CLEAN_BUILD=1
if [ "${CLEAN_BUILD:-0}" = "1" ]; then
    echo "Temiz derleme: out klasoru siliniyor..."
    rm -rf "$OUT_DIR"
fi

mkdir -p "$OUT_DIR"

MAKE_OPTS=(
    "O=$OUT_DIR"
    "CC=$CC"
    "HOSTCC=$HOSTCC"
    "HOSTCXX=$HOSTCXX"
    "LD=$LD"
    "AR=$AR"
    "NM=$NM"
    "STRIP=$STRIP"
    "OBJCOPY=$OBJCOPY"
    "OBJDUMP=$OBJDUMP"
    "HOSTAR=$HOSTAR"
    "HOSTLD=$HOSTLD"
    "LLVM=1"
    "LLVM_IAS=1"
    "LTO=thin"
)

for inc in "${INCLUDE_PATHS[@]}"; do
    MAKE_OPTS+=("$inc")
done

echo "**** Defconfig: $KERNEL_DEFCONFIG ****"
make "${MAKE_OPTS[@]}" "$KERNEL_DEFCONFIG"
make -j"$(nproc)" "${MAKE_OPTS[@]}"

if [ -d "$DTB_DTBO_DIR" ]; then
    echo "Building DTBs..."
    make -j"$(nproc)" "${MAKE_OPTS[@]}" dtbs

    DTBTOOL_DIR="$KERNEL_DIR/tools/dtbtool"
    mkdir -p "$DTBTOOL_DIR"

    if [ ! -f "$DTBTOOL_DIR/dtbtool.c" ]; then
        wget -O "$DTBTOOL_DIR/dtbtool.c" \
          "https://raw.githubusercontent.com/LineageOS/android_system_tools_dtbtool/lineage-18.1/dtbtool.c"
    fi

    gcc "$DTBTOOL_DIR/dtbtool.c" -o "$DTBTOOL_DIR/dtbtool"
    "$DTBTOOL_DIR/dtbtool" -s 2048 -o "$ZIMAGE_DIR/dt.img" "$DTB_DTBO_DIR"
fi

BUILD_HAS_MODULES=$(grep -c '=m' "$OUT_DIR/.config" || true)
MODULES_DIR="$OUT_DIR/modules_temp"

if [ "$BUILD_HAS_MODULES" -gt 0 ]; then
    echo "Building modules..."
    make -j"$(nproc)" "${MAKE_OPTS[@]}" modules

    rm -rf "$MODULES_DIR"
    mkdir -p "$MODULES_DIR"
    make "${MAKE_OPTS[@]}" INSTALL_MOD_PATH="$MODULES_DIR" INSTALL_MOD_STRIP=1 modules_install
    find "$MODULES_DIR" -type l -delete
fi

if [ -d "$KERNEL_DIR/.git" ]; then
    git -C "$KERNEL_DIR" restore -- scripts/dtc/dtc-lexer.lex.c_shipped scripts/dtc/dtc-lexer.l || true
fi

echo "Cleaning up old kernel zip files..."
find "$KERNEL_DIR" -maxdepth 1 -type f -name 'RealKing-Peridot-*.zip' -delete

TIME=$(date '+%Y%m%d-%H%M%S')
TEMP_ANY_KERNEL_DIR="$KERNEL_DIR/anykernel_temp"
rm -rf "$TEMP_ANY_KERNEL_DIR"

if [ ! -d "$KERNEL_DIR/anykernel" ]; then
    echo "HATA: anykernel klasoru bulunamadi!"
    exit 1
fi

cp -r "$KERNEL_DIR/anykernel" "$TEMP_ANY_KERNEL_DIR"

if [ -f "$ZIMAGE_DIR/Image.gz-dtb" ]; then
    cp -v "$ZIMAGE_DIR/Image.gz-dtb" "$TEMP_ANY_KERNEL_DIR/"
elif [ -f "$ZIMAGE_DIR/Image.gz" ]; then
    cp -v "$ZIMAGE_DIR/Image.gz" "$TEMP_ANY_KERNEL_DIR/"
elif [ -f "$ZIMAGE_DIR/Image" ]; then
    cp -v "$ZIMAGE_DIR/Image" "$TEMP_ANY_KERNEL_DIR/"
else
    echo "HATA: Kernel Image bulunamadi!"
    exit 1
fi

[ ! -f "$ZIMAGE_DIR/dt.img" ] || cp -v "$ZIMAGE_DIR/dt.img" "$TEMP_ANY_KERNEL_DIR/"
[ ! -f "$ZIMAGE_DIR/dtbo.img" ] || cp -v "$ZIMAGE_DIR/dtbo.img" "$TEMP_ANY_KERNEL_DIR/"

if [ "$BUILD_HAS_MODULES" -gt 0 ]; then
    mkdir -p "$TEMP_ANY_KERNEL_DIR/_modules"
    find "$TEMP_ANY_KERNEL_DIR/_modules" -maxdepth 1 -type f -name '*.ko' -delete

    IMPORTANT_MODULES=(
        ipam.ko ipanetm.ko msm_drm.ko msm_kgsl.ko
        qti_cpufreq_cdev.ko qti_devfreq_cdev.ko
        rmnet_offload.ko rmnet_shs.ko
        synaptics_tcm2.ko xiaomi_touch.ko
        cnss_nl.ko cnss_plat_ipc_qmi_svc.ko cnss_prealloc.ko
        cnss_utils.ko cnss2.ko wlan_firmware_service.ko
        mhi.ko qrtr-mhi.ko qca_cld3_kiwi_v2.ko
    )

    for module in "${IMPORTANT_MODULES[@]}"; do
        find "$MODULES_DIR/lib/modules" -name "$module" \
            -exec cp -v '{}' "$TEMP_ANY_KERNEL_DIR/_modules/" \;
    done

    echo "Modules in _modules:"
    ls -lh "$TEMP_ANY_KERNEL_DIR/_modules"
fi

ZIP_NAME="RealKing-Peridot-$TIME.zip"
echo "Creating zip package..."
(
    cd "$TEMP_ANY_KERNEL_DIR"
    zip -r9 "$KERNEL_DIR/$ZIP_NAME" ./*
)

rm -rf "$TEMP_ANY_KERNEL_DIR"

BUILD_END=$(date +%s)
DIFF=$((BUILD_END - BUILD_START))

echo
echo "Build completed in $((DIFF / 60))m $((DIFF % 60))s"
echo "Final zip: $KERNEL_DIR/$ZIP_NAME"
du -h "$KERNEL_DIR/$ZIP_NAME"
