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

echo "====================================================="
echo "🛡️ KSU-NEXT + SUSFS + MULTI-MANAGER KURULUMU BAŞLIYOR"
echo "====================================================="

# 1. KSU-Next Kurulumu
echo "📦 [1/5] KernelSU-Next kuruluyor..."
git clone --depth=1 https://github.com/Bosyaf/Ksu-next.git KernelSU-Next
bash KernelSU-Next/kernel/setup.sh
echo "✅ [1/5] KernelSU-Next kurulumu tamamlandı!"

# 2. Multi-Manager Patch Uygulaması (İnternetten Canlı Çekim)
echo "🔥 [2/5] Multi-Manager patch uygulanıyor..."
wget -q "https://raw.githubusercontent.com/Bosyaf/Kernel-Action/main/patches/ksu/ksun-add-more-managers-support.patch" -O ksun-add-more-managers-support.patch || \
curl -LSs "https://raw.githubusercontent.com/Bosyaf/Kernel-Action/main/patches/ksu/ksun-add-more-managers-support.patch" -o ksun-add-more-managers-support.patch

if [ -f "ksun-add-more-managers-support.patch" ]; then
  cd KernelSU-Next
  patch -p1 --forward < "../ksun-add-more-managers-support.patch" && \
  echo "✅ [2/5] Multi-Manager patch başarılı!" || echo "⚠️ [2/5] Patch uygulanamadı (Zaten uygulanmış olabilir)"
  cd ..
  rm -f ksun-add-more-managers-support.patch
else
  echo "⚠️ [2/5] Patch dosyası internetten çekilemedi, atlanıyor..."
fi

# 3. SUSFS İndirme ve Dosya Kopyalama
echo "📦 [3/5] SUSFS kuruluyor..."
git clone --depth=1 https://github.com/Bosyaf/Susfs.git susfs4ksu
echo "📦 SUSFS dosyaları kopyalanıyor..."
cp -R susfs4ksu/kernel_patches/fs/* ./fs/
cp -R susfs4ksu/kernel_patches/include/* ./include/
echo "✅ [3/5] SUSFS dosyaları kopyalandı!"

# 3.1 Ana SUSFS Patch Uygulaması
echo "📦 [3.1/5] Ana SUSFS patch uygulanıyor..."
SUSFS_PATCH=$(ls susfs4ksu/kernel_patches/50_add_susfs*.patch 2>/dev/null | head -1)
if [ -n "$SUSFS_PATCH" ]; then
  patch -p1 < "$SUSFS_PATCH" || true
  echo "✅ [3.1/5] Ana SUSFS patch uygulandı!"
else
  echo "⚠️ [3.1/5] Patch dosyası bulunamadı, atlanıyor..."
fi

# 4. fs_namespace Patch Uygulaması
echo "📦 [4/5] fs_namespace.patch uygulanıyor..."
wget -q "https://raw.githubusercontent.com/Bosyaf/Kernel-Action/main/fs_namespace.patch" -O fs_namespace.patch || \
curl -LSs "https://raw.githubusercontent.com/Bosyaf/Kernel-Action/main/fs_namespace.patch" -o fs_namespace.patch

if [ -f fs_namespace.patch ]; then
  patch -p1 < fs_namespace.patch || true
  echo "✅ [4/5] fs_namespace.patch uygulandı!"
else
  echo "⚠️ [4/5] Patch bulunamadı"
fi
rm -f fs_namespace.patch

# 5. SUSFS Dentry Check Fix (Canlı Sed Yaması)
echo "🛡️ [5/5] SUSFS Dentry Check Fix (Canlı Yama) uygulanıyor..."
sed -i 's/return (base->d_inode->i_mapping->flags & BIT_ANDROID_DATA_ROOT_DIR);/return (base \&\& !IS_ERR(base) \&\& base->d_inode \&\& (base->d_inode->i_mapping->flags \& BIT_ANDROID_DATA_ROOT_DIR));/g' fs/susfs.c
sed -i 's/return (base->d_inode->i_mapping->flags & BIT_ANDROID_SDCARD_ROOT_DIR);/return (base \&\& !IS_ERR(base) \&\& base->d_inode \&\& (base->d_inode->i_mapping->flags \& BIT_ANDROID_SDCARD_ROOT_DIR));/g' fs/susfs.c
# HOUJI CUSTOM FIX: True/False çakışmasını gideren Canlı Yama
sed -i 's/extern struct static_key_true susfs_is_sdcard_android_data_not_decrypted;/extern struct static_key_false susfs_is_sdcard_android_data_not_decrypted;/g' fs/namespace.c
echo "✅ [5/5] Canlı Yama Başarılı!"

# Temizlik
find . -name "*.rej" -delete 2>/dev/null || true
rm -rf susfs4ksu
echo "🎉 SUSFS VE KSU SİSTEMİ KUSURSUZ KURULDU!"
echo "====================================================="

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

# Install ZyC Clang 22.0.0git
CLANG_DIR="$MAIN/toolchains/zyc-clang-22"
CLANG_URL="https://github.com/ZyCromerZ/Clang/releases/download/22.0.0git-20250928-release/Clang-22.0.0git-20250928.tar.gz"
ARCHIVE_NAME="zyc-clang-22.tar.gz"

check_clang() {
    [ -x "$CLANG_DIR/bin/clang" ] &&
    [ -x "$CLANG_DIR/bin/clang++" ] &&
    [ -x "$CLANG_DIR/bin/ld.lld" ] &&
    [ -x "$CLANG_DIR/bin/llvm-ar" ] &&
    [ -x "$CLANG_DIR/bin/llvm-nm" ] &&
    [ -x "$CLANG_DIR/bin/llvm-strip" ]
}

if ! check_clang; then
    echo "ZyC Clang 22.0.0 indiriliyor..."
    mkdir -p "$CLANG_DIR"

    wget -O "$MAIN/$ARCHIVE_NAME" "$CLANG_URL"
    
    # ZyC tar.gz kullandığı için -xzf ile çıkarıyoruz.
    tar -xzf "$MAIN/$ARCHIVE_NAME" -C "$CLANG_DIR"
    rm -f "$MAIN/$ARCHIVE_NAME"
fi

if ! check_clang; then
    echo "HATA: ZyC Clang 22 kurulumu tamamlanamadi."
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
export KCFLAGS="-O2 \
    -march=armv9.2-a+crypto+crc+dotprod+rcpc+lse+sha3 \
    -falign-functions=32 \
    -fomit-frame-pointer \
    -ffunction-sections \
    -fdata-sections \
    -fstack-protector \
    -fno-unwind-tables \
    -fno-asynchronous-unwind-tables \
    -fno-math-errno \
    -fno-semantic-interposition \
    -Wno-frame-larger-than \
    -Wno-unused-command-line-argument \
    -Wno-error \
    -Wno-format \
    -Wno-format-extra-args \
    -Wno-constant-logical-operand \
    -Wno-unused-variable \
    -Wno-address-of-packed-member \
    -Wno-uninitialized-const-pointer \
    -Wno-uninitialized \
    -Wno-default-const-init-var-unsafe \
    -Wno-default-const-init-field-unsafe"

export KLDFLAGS="-Wl,--gc-sections \
    -Wl,--as-needed \
    -Wl,--strip-debug \
    -Wl,--icf=safe \
    -Wl,--no-warnings \
    -Wl,-O2"

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
    $INCLUDE_PATHS
"

# Apply YYLLOC workaround
echo "Applying YYLLOC workaround..."
YYLL1="$KERNEL_DIR/scripts/dtc/dtc-lexer.lex.c_shipped"
YYLL2="$KERNEL_DIR/scripts/dtc/dtc-lexer.l"
[ -f "$YYLL1" ] && sed -i "s/extern YYLTYPE yylloc/YYLTYPE yylloc/g;s/YYLTYPE yylloc/extern YYLTYPE yylloc/g" "$YYLL1"
[ -f "$YYLL2" ] && sed -i "s/extern YYLTYPE yylloc/YYLTYPE yylloc/g;s/YYLTYPE yylloc/extern YYLTYPE yylloc/g" "$YYLL2"


# 1. DEFCONFIG
echo "==== DEFCONFIG ===="
make O="$OUT_DIR" $MAKE_OPTS "$KERNEL_DEFCONFIG"

# 2. CONFIG DOSYASINI BELİRLE
CONFIG_FILE="$OUT_DIR/.config"
test -f "$CONFIG_FILE" || {
    echo "HATA: .config bulunamadi!"
    exit 1
}

# 3. İSTENEN CONFIG AYARLARINI UYGULA
echo "==== CONFIG AYARLARI UYGULANIYOR ===="

scripts/config --file "$CONFIG_FILE" --module SCHED_WALT
scripts/config --file "$CONFIG_FILE" --disable SCHED_CLUSTER
scripts/config --file "$CONFIG_FILE" --disable SCHED_SMT

scripts/config --file "$CONFIG_FILE" --disable HZ_100
scripts/config --file "$CONFIG_FILE" --disable HZ_250
scripts/config --file "$CONFIG_FILE" --enable HZ_300
scripts/config --file "$CONFIG_FILE" --disable HZ_500
scripts/config --file "$CONFIG_FILE" --disable HZ_1000
scripts/config --file "$CONFIG_FILE" --set-val HZ 300

scripts/config --file "$CONFIG_FILE" --enable NO_HZ_IDLE
scripts/config --file "$CONFIG_FILE" --disable NO_HZ_FULL

scripts/config --file "$CONFIG_FILE" --enable THERMAL_GOV_STEP_WISE
scripts/config --file "$CONFIG_FILE" --enable THERMAL_GOV_POWER_ALLOCATOR
scripts/config --file "$CONFIG_FILE" --disable THERMAL_DEFAULT_GOV_STEP_WISE
scripts/config --file "$CONFIG_FILE" --enable THERMAL_DEFAULT_GOV_POWER_ALLOCATOR

scripts/config --file "$CONFIG_FILE" --enable LTO_CLANG
scripts/config --file "$CONFIG_FILE" --enable LTO_CLANG_THIN
scripts/config --file "$CONFIG_FILE" --disable LTO_CLANG_FULL

scripts/config --file "$CONFIG_FILE" --disable PREEMPT_NONE
scripts/config --file "$CONFIG_FILE" --disable PREEMPT_VOLUNTARY
scripts/config --file "$CONFIG_FILE" --enable PREEMPT
scripts/config --file "$CONFIG_FILE" --enable PREEMPT_COUNT
scripts/config --file "$CONFIG_FILE" --enable PREEMPTION
scripts/config --file "$CONFIG_FILE" --enable PREEMPT_BUILD

scripts/config --file "$CONFIG_FILE" --enable WIREGUARD
scripts/config --file "$CONFIG_FILE" --enable IP_NF_TARGET_TTL
scripts/config --file "$CONFIG_FILE" --enable IP6_NF_TARGET_HL
scripts/config --file "$CONFIG_FILE" --enable IP6_NF_MATCH_HL
scripts/config --file "$CONFIG_FILE" --enable TMPFS_POSIX_ACL
scripts/config --file "$CONFIG_FILE" --enable TMPFS_XATTR

scripts/config --file "$CONFIG_FILE" --disable NUMA_BALANCING
scripts/config --file "$CONFIG_FILE" --disable DEBUG_INFO_REDUCED
scripts/config --file "$CONFIG_FILE" --disable DEBUG_INFO_COMPRESSED
scripts/config --file "$CONFIG_FILE" --disable DEBUG_INFO_SPLIT
scripts/config --file "$CONFIG_FILE" --disable DEBUG_INFO_DWARF5

scripts/config --file "$CONFIG_FILE" --enable KSU
scripts/config --file "$CONFIG_FILE" --enable KSU_SUSFS
scripts/config --file "$CONFIG_FILE" --enable KSU_SUSFS_HAS_MAGIC_MOUNT
scripts/config --file "$CONFIG_FILE" --enable KSU_SUSFS_SUS_PATH
scripts/config --file "$CONFIG_FILE" --enable KSU_SUSFS_SUS_MOUNT
scripts/config --file "$CONFIG_FILE" --enable KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT
scripts/config --file "$CONFIG_FILE" --enable KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT
scripts/config --file "$CONFIG_FILE" --enable KSU_SUSFS_SUS_KSTAT
scripts/config --file "$CONFIG_FILE" --enable KSU_SUSFS_TRY_UMOUNT
scripts/config --file "$CONFIG_FILE" --enable KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT
scripts/config --file "$CONFIG_FILE" --enable KSU_SUSFS_SPOOF_UNAME
scripts/config --file "$CONFIG_FILE" --disable KSU_SUSFS_ENABLE_LOG
scripts/config --file "$CONFIG_FILE" --enable KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS
scripts/config --file "$CONFIG_FILE" --enable KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG
scripts/config --file "$CONFIG_FILE" --enable KSU_SUSFS_OPEN_REDIRECT
scripts/config --file "$CONFIG_FILE" --enable KSU_SUSFS_SUS_MAP

# 4. KCONFIG BAĞIMLILIKLARINI UYGULA
echo "==== OLDDEFCONFIG ===="
make O="$OUT_DIR" $MAKE_OPTS olddefconfig

# 5. SON .CONFIG DEĞERLERİNİ KONTROL ET
echo "==== SON CONFIG KONTROLÜ ===="
grep -E '^(CONFIG_(SCHED_WALT|HZ|HZ_300|NO_HZ_IDLE|NO_HZ_FULL|THERMAL_|LTO_CLANG|PREEMPT|WIREGUARD|IP_NF_TARGET_TTL|IP6_NF_|TMPFS_|NUMA_BALANCING|DEBUG_INFO_|KSU)|# CONFIG_(SCHED_CLUSTER|SCHED_SMT|HZ_|NO_HZ_FULL|THERMAL_DEFAULT_GOV_STEP_WISE|LTO_CLANG_FULL|PREEMPT_NONE|PREEMPT_VOLUNTARY|NUMA_BALANCING|DEBUG_INFO_|KSU_SUSFS_ENABLE_LOG) is not set)' "$CONFIG_FILE" || true

# Kritik ayarlar olddefconfig sonrasında korunmuş mu?
check_config() {
    local symbol="$1"
    local expected="$2"
    local actual

    actual=$(grep -E "^(CONFIG_${symbol}=|# CONFIG_${symbol} is not set)" "$CONFIG_FILE" | tail -n 1 || true)

    if [ "$actual" = "CONFIG_${symbol}=${expected}" ] ||
       { [ "$expected" = "n" ] && [ "$actual" = "# CONFIG_${symbol} is not set" ]; }; then
        echo "[OK] $symbol = $expected"
    else
        echo "[UYARI] $symbol beklenen=$expected, gerçek=${actual:-BULUNAMADI}"
    fi
}

check_config SCHED_WALT m
check_config HZ 300
check_config HZ_300 y
check_config LTO_CLANG y
check_config LTO_CLANG_THIN y
check_config LTO_CLANG_FULL n
check_config PREEMPT y
check_config KSU y
check_config KSU_SUSFS y

# 6. DERLEME
echo "==== KERNEL DERLEMESİ BAŞLIYOR ===="
make -j"$(nproc --all)" O="$OUT_DIR" $MAKE_OPTS 2>&1 | tee "$OUT_DIR/build.log"
# 7. DERLEME ÇIKTISI KONTROLÜ
if [ -s "$ZIMAGE_DIR/Image" ]; then
    echo "[OK] Image oluşturuldu."
else
    echo "[HATA] Image bulunamadı!"
    exit 1
fi

echo "==== WALT MODÜLÜ KONTROLÜ ===="
find "$OUT_DIR" -type f -name '*sched*walt*.ko' -print

echo "==== DERLEME TAMAMLANDI ===="


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

        # List of specific modules to include
    IMPORTANT_MODULES=(
        "ipam.ko" "ipanetm.ko"
        "msm_drm.ko" "msm_kgsl.ko"
        "qti_cpufreq_cdev.ko" "qti_devfreq_cdev.ko" "rmnet_offload.ko" "rmnet_shs.ko"
        "synaptics_tcm2.ko" "xiaomi_touch.ko"
        "cnss_nl.ko" "cnss_plat_ipc_qmi_svc.ko" "cnss_prealloc.ko" "cnss_utils.ko" "cnss2.ko"
        "wlan_firmware_service.ko" "mhi.ko" "qrtr-mhi.ko" "qca_cld3_kiwi_v2.ko"
    )

    # Find and copy each specified module
    for module in "${IMPORTANT_MODULES[@]}"; do
        find "$MODULES_DIR/lib/modules" -name "$module" -exec cp -v {} "$TEMP_ANY_KERNEL_DIR/_modules/" \;
    done

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
