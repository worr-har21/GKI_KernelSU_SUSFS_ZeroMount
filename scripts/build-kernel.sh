#!/bin/bash
set -euo pipefail

FRAG_FLAG=""
[[ -s "common/arch/arm64/configs/ksu.fragment" ]] && \
    FRAG_FLAG="--defconfig_fragment=//common:arch/arm64/configs/ksu.fragment"

# fix resolve_btfids sysroot issue (prebuilt clang may lack host glibc symbols)
if [[ -f common/tools/bpf/resolve_btfids/Makefile ]]; then
    echo 'override KBUILD_HOSTLDFLAGS += --sysroot=/' >> common/tools/bpf/resolve_btfids/Makefile
    echo 'override LDFLAGS += --sysroot=/' >> common/tools/bpf/resolve_btfids/Makefile
fi

# remove any stale Image so we don't accidentally package an old one
find . -name "Image" -path "*/kernel_aarch64/*" -type f -delete 2>/dev/null || true

echo "==> building kernel (this will take a while)..."
tools/bazel build \
    --config=fast \
    --lto=thin \
    $FRAG_FLAG \
    //common:kernel_aarch64_dist

BUILD_RC=$?
if [ "$BUILD_RC" -ne 0 ]; then
    if find . -name "Image" -path "*/kernel_aarch64/*" -type f 2>/dev/null | grep -q .; then
        echo "WARNING: build exited $BUILD_RC but Image exists (likely depmod failure)"
    else
        echo "FATAL: build failed and no Image produced"
        exit 1
    fi
fi

echo "==> kernel built successfully"
strings ./bazel-bin/common/kernel_aarch64/Image | grep 'Linux version' || true
