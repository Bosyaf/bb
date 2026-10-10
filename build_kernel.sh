#!/bin/bash
set -e

# Configuration
DIR=$(readlink -f .)
MAIN=$(readlink -f ${DIR}/..)
KERNEL_DEFCONFIG=shen_gki_defconfig
CLANG_DIR="$MAIN/toolchains/clang-1"
KERNEL_DIR=$(pwd)
OUT_DIR="$KERNEL_DIR/out"
ZIMAGE_DIR="$OUT_DIR/arch/arm64/boot"
DTB_DTBO_DIR="$ZIMAGE_DIR/dts/vendor/qcom"
BUILD_START=$(date +"%s")
export WLAN_CTRL_NAME=wlan
export BOARD_PLATFORM=pineapple
export DEVNAME=kiwi_v2
export MODNAME=qca_cld3_kiwi_v2
export DYNAMIC_SINGLE_CHIP=kiwi_v2
export WLAN_PROFILE=kiwi_v2
# Techpack paths
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


# KernelSU-Next & Multi-Manager
echo "[1/5] KernelSU-Next kuruluyor (Bosyaf/Ksu-next)..."

cd "$KERNEL_DIR/common"
rm -rf KernelSU-Next
git clone --depth=1 https://github.com/Bosyaf/Ksu-next.git KernelSU-Next
bash KernelSU-Next/kernel/setup.sh

echo "[2/5] Multi-Manager patch uygulanıyor..."
PATCH="$KERNEL_DIR/patches/ksu/ksun-add-more-managers-support.patch"

if [ -f "$PATCH" ]; then
    cd "$KERNEL_DIR/common/KernelSU-Next"
    if patch -p1 --forward < "$PATCH"; then
        echo "Multi-Manager patch uygulandı."
    else
        echo "UYARI: Multi-Manager patch uygulanamadı."
    fi
else
    echo "UYARI: Multi-Manager patch bulunamadı."
fi

# SUSFS4KSU
echo "[3/5] SUSFS4KSU kuruluyor..."
cd "$KERNEL_DIR/common"
rm -rf susfs4ksu
git clone --depth=1 https://github.com/Bosyaf/Susfs.git susfs4ksu

cp -R susfs4ksu/kernel_patches/fs/* ./fs/
cp -R susfs4ksu/kernel_patches/include/* ./include/

SUSFS_PATCH=$(find susfs4ksu/kernel_patches -maxdepth 1 \
    -name '50_add_susfs*.patch' -print -quit)

if [ -n "$SUSFS_PATCH" ]; then
    patch -p1 < "$SUSFS_PATCH" || true
else
    echo "UYARI: Ana SUSFS patch bulunamadı."
fi

echo "[4/5] fs_namespace.patch uygulanıyor..."
wget -q \
    "https://raw.githubusercontent.com/Bosyaf/Kernel-Action/main/fs_namespace.patch" \
    -O fs_namespace.patch ||
curl -fLSs \
    "https://raw.githubusercontent.com/Bosyaf/Kernel-Action/main/fs_namespace.patch" \
    -o fs_namespace.patch

if [ -s fs_namespace.patch ]; then
    patch -p1 < fs_namespace.patch || true
else
    echo "UYARI: fs_namespace.patch indirilemedi."
fi
rm -f fs_namespace.patch

echo "[5/5] SUSFS Dentry Check Fix uygulanıyor..."
sed -i \
's/return (base->d_inode->i_mapping->flags & BIT_ANDROID_DATA_ROOT_DIR);/return (base \&\& !IS_ERR(base) \&\& base->d_inode \&\& (base->d_inode->i_mapping->flags \& BIT_ANDROID_DATA_ROOT_DIR));/g' \
fs/susfs.c

sed -i \
's/return (base->d_inode->i_mapping->flags & BIT_ANDROID_SDCARD_ROOT_DIR);/return (base \&\& !IS_ERR(base) \&\& base->d_inode \&\& (base->d_inode->i_mapping->flags \& BIT_ANDROID_SDCARD_ROOT_DIR));/g' \
fs/susfs.c

find "$KERNEL_DIR/common" -name '*.rej' -delete 2>/dev/null || true
rm -rf "$KERNEL_DIR/common/susfs4ksu"

cd "$KERNEL_DIR"

# Function to check for existing Clang
check_clang() {
    if [ -d "$CLANG_DIR" ] && [ -f "$CLANG_DIR/bin/clang" ]; then
        export PATH="$CLANG_DIR/bin:$PATH"
        export KBUILD_COMPILER_STRING="$($CLANG_DIR/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')"
        echo "Found existing Clang: $KBUILD_COMPILER_STRING"
        return 0
    fi
    return 1
}

# Install LLVM/Clang 17.0.2 if needed
CLANG_DIR="$MAIN/toolchains/clang-17.0.2"
CLANG_URL="https://github.com/llvm/llvm-project/releases/download/llvmorg-17.0.2/clang%2Bllvm-17.0.2-x86_64-linux-gnu-ubuntu-22.04.tar.xz"
ARCHIVE_NAME="clang-17.0.2.tar.xz"

check_clang() {
    [ -x "$CLANG_DIR/bin/clang" ] &&
    [ -x "$CLANG_DIR/bin/clang++" ] &&
    [ -x "$CLANG_DIR/bin/ld.lld" ] &&
    [ -x "$CLANG_DIR/bin/llvm-ar" ] &&
    [ -x "$CLANG_DIR/bin/llvm-nm" ] &&
    [ -x "$CLANG_DIR/bin/llvm-strip" ]
}

if ! check_clang; then
    echo "LLVM/Clang 17.0.2 indiriliyor..."
    mkdir -p "$CLANG_DIR"

    wget -O "$MAIN/$ARCHIVE_NAME" "$CLANG_URL"
    tar -xJf "$MAIN/$ARCHIVE_NAME" \
        --strip-components=1 -C "$CLANG_DIR"
    rm -f "$MAIN/$ARCHIVE_NAME"
fi

if ! check_clang; then
    echo "HATA: LLVM/Clang 17.0.2 kurulumu tamamlanamadi."
    ls -lah "$CLANG_DIR"
    ls -lah "$CLANG_DIR/bin" || true
    exit 1
fi

# Use the same LLVM toolchain for compiler and linker
export PATH="$CLANG_DIR/bin:$PATH"
export CC="$CLANG_DIR/bin/clang"
export CXX="$CLANG_DIR/bin/clang++"
export HOSTCC="$CLANG_DIR/bin/clang"
export HOSTCXX="$CLANG_DIR/bin/clang++"
export LD="$CLANG_DIR/bin/ld.lld"
export HOSTLD="$CLANG_DIR/bin/ld.lld"
export AR="$CLANG_DIR/bin/llvm-ar"
export HOSTAR="$CLANG_DIR/bin/llvm-ar"
export NM="$CLANG_DIR/bin/llvm-nm"
export STRIP="$CLANG_DIR/bin/llvm-strip"
export OBJCOPY="$CLANG_DIR/bin/llvm-objcopy"
export OBJDUMP="$CLANG_DIR/bin/llvm-objdump"
export LLVM=1
export LLVM_IAS=1

export KBUILD_COMPILER_STRING="$("$CC" --version | head -n 1)"
echo "Kullanilan Clang: $KBUILD_COMPILER_STRING"
echo "Kullanilan LLD: $("$LD" --version | head -n 1)"

# Set up target
export ARCH=arm64
export SUBARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-

# Include paths
export KERNEL_SRC="$KERNEL_DIR"
INCLUDE_PATHS="
    -I$KERNEL_DIR/include
    -I$KERNEL_DIR/arch/arm64/include
    -I$KERNEL_DIR/drivers/base/regmap
    -I$AUDIO_ROOT/include
    -I$CAMERA_ROOT/include
    -I$DISPLAY_ROOT/include
"

# Build flags
MAKE_OPTS="
    CC=clang
    STRIP=llvm-strip
    LD=ld.lld
    AR=llvm-ar
    NM=llvm-nm
    OBJCOPY=llvm-objcopy
    OBJDUMP=llvm-objdump
    HOSTCC=clang
    HOSTCXX=clang++
    HOSTAR=llvm-ar
    HOSTLD=ld.lld
    LLVM=1
    LLVM_IAS=1
    LTO=thin
    KCFLAGS=-march=armv8.4-a
    KCFLAGS=-march=armv9.2-a
    $INCLUDE_PATHS
"

# Apply YYLLOC workaround
echo "Applying YYLLOC workaround..."
YYLL1="$KERNEL_DIR/scripts/dtc/dtc-lexer.lex.c_shipped"
YYLL2="$KERNEL_DIR/scripts/dtc/dtc-lexer.l"
[ -f "$YYLL1" ] && sed -i "s/extern YYLTYPE yylloc/YYLTYPE yylloc/g;s/YYLTYPE yylloc/extern YYLTYPE yylloc/g" "$YYLL1"
[ -f "$YYLL2" ] && sed -i "s/extern YYLTYPE yylloc/YYLTYPE yylloc/g;s/YYLTYPE yylloc/extern YYLTYPE yylloc/g" "$YYLL2"

# Start build process
echo "**** Building with $KBUILD_COMPILER_STRING ****"
echo "**** Defconfig: $KERNEL_DEFCONFIG ****"

# Build kernel
make O="$OUT_DIR" $KERNEL_DEFCONFIG $MAKE_OPTS || exit 1
make -j$(nproc --all) O="$OUT_DIR" $MAKE_OPTS || exit 1

# Build DTB/DTBO if they exist
if [ -d "$DTB_DTBO_DIR" ]; then
    echo "Building DTBs..."
    make -j$(nproc --all) O="$OUT_DIR" $MAKE_OPTS dtbs || exit 1

    # Create dt.img using dtbtool
    echo "Creating dt.img..."
    DTBTOOL_DIR="$KERNEL_DIR/tools/dtbtool"
    mkdir -p "$DTBTOOL_DIR"
    if [ ! -f "$DTBTOOL_DIR/dtbtool.c" ]; then
        wget -q https://raw.githubusercontent.com/LineageOS/android_system_tools_dtbtool/lineage-18.1/dtbtool.c -O "$DTBTOOL_DIR/dtbtool.c"
    fi
    gcc "$DTBTOOL_DIR/dtbtool.c" -o "$DTBTOOL_DIR/dtbtool" >/dev/null 2>&1
    "$DTBTOOL_DIR/dtbtool" -s 2048 -o "$ZIMAGE_DIR/dt.img" "$DTB_DTBO_DIR" >/dev/null 2>&1
fi

# Build modules
BUILD_HAS_MODULES=$(grep "=m" "$OUT_DIR/.config" | wc -l)
if [ $BUILD_HAS_MODULES -gt 0 ]; then
    echo "Building modules..."
    make -j$(nproc --all) O="$OUT_DIR" $MAKE_OPTS modules || exit 1

    # Install modules to temporary directory
    MODULES_DIR="$OUT_DIR/modules_temp"
    rm -rf "$MODULES_DIR"
    mkdir -p "$MODULES_DIR"
    make O="$OUT_DIR" INSTALL_MOD_PATH="$MODULES_DIR" INSTALL_MOD_STRIP=1 modules_install || exit 1

    # Clean up symlinks
    find "$MODULES_DIR" -type l -delete
fi

# Restore YYLL files if in git repo
[ -d "$KERNEL_DIR"/.git ] && git restore "$YYLL1" "$YYLL2" 2>/dev/null || true

# Clean up old kernel zip files
echo "Cleaning up old kernel zip files..."
find "$KERNEL_DIR" -maxdepth 1 -type f -name "RealKing-Peridot-*.zip" -exec rm -v {} \;

# Create temporary anykernel directory
TIME=$(date "+%Y%m%d-%H%M%S")
TEMP_ANY_KERNEL_DIR="$KERNEL_DIR/anykernel_temp"
rm -rf "$TEMP_ANY_KERNEL_DIR"

# Clone entire anykernel directory
echo "Cloning anykernel directory..."
if [ -d "$KERNEL_DIR/anykernel" ]; then
    cp -r "$KERNEL_DIR/anykernel" "$TEMP_ANY_KERNEL_DIR"
else
    echo "Error: anykernel directory not found!"
    exit 1
fi

# Copy kernel image
if [ -f "$ZIMAGE_DIR/Image.gz-dtb" ]; then
    cp -v "$ZIMAGE_DIR/Image.gz-dtb" "$TEMP_ANY_KERNEL_DIR/"
elif [ -f "$ZIMAGE_DIR/Image.gz" ]; then
    cp -v "$ZIMAGE_DIR/Image.gz" "$TEMP_ANY_KERNEL_DIR/"
elif [ -f "$ZIMAGE_DIR/Image" ]; then
    cp -v "$ZIMAGE_DIR/Image" "$TEMP_ANY_KERNEL_DIR/"
fi

# Copy DTBs if they exist
[ -f "$ZIMAGE_DIR/dt.img" ] && cp -v "$ZIMAGE_DIR/dt.img" "$TEMP_ANY_KERNEL_DIR/"
[ -f "$ZIMAGE_DIR/dtbo.img" ] && cp -v "$ZIMAGE_DIR/dtbo.img" "$TEMP_ANY_KERNEL_DIR/"

# Handle _modules directory
if [ $BUILD_HAS_MODULES -gt 0 ]; then
    echo "Preparing _modules directory..."

    # Check if _modules exists in template
    if [ -d "$TEMP_ANY_KERNEL_DIR/_modules" ]; then
        echo "Found existing _modules directory, clearing contents..."
        rm -f "$TEMP_ANY_KERNEL_DIR/_modules"/*.ko
    else
        echo "Creating _modules directory..."
        mkdir -p "$TEMP_ANY_KERNEL_DIR/_modules"
    fi

    # Copy all compiled modules
    find "$MODULES_DIR/lib/modules" -name "*.ko" -exec cp -v {} "$TEMP_ANY_KERNEL_DIR/_modules/" \;

    echo "Modules in _modules:"
    ls -lh "$TEMP_ANY_KERNEL_DIR/_modules"
fi

# Create zip file in kernel root directory
echo "Creating zip package..."
ZIP_NAME="RealKing-Peridot-$TIME.zip"
cd "$TEMP_ANY_KERNEL_DIR"
zip -r9 "$KERNEL_DIR/$ZIP_NAME" ./*
cd ..

# Clean up temporary directory
rm -rf "$TEMP_ANY_KERNEL_DIR"

BUILD_END=$(date +"%s")
DIFF=$((BUILD_END - BUILD_START))
echo -e "\nBuild completed in $((DIFF / 60))m $((DIFF % 60))s"
echo "Final zip: $KERNEL_DIR/$ZIP_NAME"
echo "Zip size: $(du -h "$KERNEL_DIR/$ZIP_NAME" | cut -f1)"

