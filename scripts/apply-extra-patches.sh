#!/bin/bash
set -euo pipefail

KERNEL_VERSION="$1"
# Mount point from Podman inside the container
PATCH_DIR="/build/repo/patches/extra"

echo "==> applying extra GKI patches for container compatibility..."

# 1. Ignore symbols crc check
patch -p1 -F3 < "$PATCH_DIR/01.disable_crc_checks_for_lkms.patch"

# 2. Fix cgroup file prefix handling
patch -p1 -F3 < "$PATCH_DIR/02.fix_restore cgroup file prefix handling .patch"

# 3. Apply POSIX_MQUEUE conditionally based on kernel version
MAJOR=$(echo "$KERNEL_VERSION" | cut -d. -f1)
MINOR=$(echo "$KERNEL_VERSION" | cut -d. -f2)

if [ "$MAJOR" -lt 5 ] || { [ "$MAJOR" -eq 5 ] && [ "$MINOR" -le 10 ]; }; then
    echo "  -> Using 5.10 or lower POSIX_MQUEUE patch"
    patch -p1 -F3 < "$PATCH_DIR/03.5.10_or_lower_use_android_abi_padding_for_posix_mqueue copy.patch"
else
    echo "  -> Using 5.15+ POSIX_MQUEUE patch"
    patch -p1 -F3 < "$PATCH_DIR/03.5.15+_use_android_abi_padding_for_posix_mqueue.patch"
fi

# 4. Use Android ABI padding for SYSVIPC task_struct fields
patch -p1 -F3 < "$PATCH_DIR/04.use_android_abi_padding_for_sysvipc_task_struct.patch"

echo "==> extra GKI patches applied"
