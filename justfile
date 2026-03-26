# === configuration ===
ANDROID_VERSION := env_var_or_default("ANDROID_VERSION", "android1")
KERNEL_VERSION := env_var_or_default("KERNEL_VERSION", "6.6")
SUB_LEVEL := env_var_or_default("SUB_LEVEL", "102")
OS_PATCH_LEVEL := env_var_or_default("OS_PATCH_LEVEL", "2026-01")
KSU_VARIANT := env_var_or_default("KSU_VARIANT", "ReSukiSU")

# container
CONTAINER_IMAGE := "gki-kernel-builder"
PODMAN := "podman run --rm --pids-limit=0"

# derived
KERNEL_BRANCH := ANDROID_VERSION + "-" + KERNEL_VERSION + "-" + OS_PATCH_LEVEL

# default target
default: build-all

# full build pipeline
build-all: build-container fetch-deps sync-kernel setup-ksu apply-susfs apply-zeromount apply-zram apply-extra-patches configure build-kernel package

# clean all build artefacts and sources
clean:
    rm -rfv src/ out/ tmp/

# build the container image
build-container:
    podman build -t {{CONTAINER_IMAGE}} -f Containerfile .

# fetch dependency repos
fetch-deps:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p src/ out/ tmp/
    echo "==> cloning GKI_KernelSU_SUSFS config repo..."
    [[ -d tmp/gki-config ]] || git clone --depth 1 git@github.com:zzh20188/GKI_KernelSU_SUSFS.git tmp/gki-config
    echo "==> cloning Super-Builders (for zeromount patch)..."
    [[ -d tmp/super-builders ]] || git clone --depth 1 git@github.com:Enginex0/Super-Builders.git tmp/super-builders
    echo "==> cloning SUSFS..."
    [[ -d tmp/susfs4ksu ]] || git clone --depth 1 https://gitlab.com/simonpunk/susfs4ksu.git -b "gki-{{ANDROID_VERSION}}-{{KERNEL_VERSION}}" tmp/susfs4ksu
    echo "==> cloning AnyKernel3..."
    if [[ ! -d tmp/anykernel3 ]]; then
        git clone --depth 1 https://github.com/WildKernels/AnyKernel3.git -b gki-2.0 tmp/anykernel3
        rm -rf tmp/anykernel3/.git
    fi
    echo "==> cloning kernel patches..."
    [[ -d tmp/kernel_patches ]] || git clone --depth 1 https://github.com/WildKernels/kernel_patches.git tmp/kernel_patches
    echo "==> cloning SukiSU patches (for zram/lz4k)..."
    [[ -d tmp/sukisu_patch ]] || git clone --depth 1 https://github.com/ShirkNeko/SukiSU_patch.git tmp/sukisu_patch
    echo "==> cloning Action-Build (for unicode fix)..."
    [[ -d tmp/action-build ]] || git clone --depth 1 https://github.com/Numbersf/Action-Build.git tmp/action-build

# sync aosp gki kernel source via repo
sync-kernel:
    {{PODMAN}} -v "$(pwd)/src:/build/src:Z" -w /build/src -v "$(pwd)/scripts:/build/scripts:ro,Z" {{CONTAINER_IMAGE}} /build/scripts/sync-kernel.sh "{{KERNEL_BRANCH}}"

# add resukisu to the kernel tree
setup-ksu:
    {{PODMAN}} -v "$(pwd)/src:/build/src:Z" -w /build/src -v "$(pwd)/scripts:/build/scripts:ro,Z" {{CONTAINER_IMAGE}} /build/scripts/setup-ksu.sh "{{KSU_VARIANT}}"

# apply susfs patches to the kernel
apply-susfs:
    {{PODMAN}} -v "$(pwd)/src:/build/src:Z" -v "$(pwd)/tmp:/build/tmp:ro,Z" -v "$(pwd)/scripts:/build/scripts:ro,Z" -w /build/src/common {{CONTAINER_IMAGE}} /build/scripts/apply-susfs.sh "{{ANDROID_VERSION}}" "{{KERNEL_VERSION}}" "{{SUB_LEVEL}}"

# apply zeromount patch from super-builders
apply-zeromount:
    {{PODMAN}} -v "$(pwd):/build/repo:ro,Z" -v "$(pwd)/src:/build/src:Z" -v "$(pwd)/tmp:/build/tmp:ro,Z" -v "$(pwd)/scripts:/build/scripts:ro,Z" -w /build/src/common {{CONTAINER_IMAGE}} /build/scripts/apply-zeromount.sh "{{ANDROID_VERSION}}" "{{KERNEL_VERSION}}"

# apply zram lz4 patches (lz4 upgrade + lz4kd)
apply-zram:
    {{PODMAN}} -v "$(pwd)/src:/build/src:Z" -v "$(pwd)/tmp:/build/tmp:ro,Z" -v "$(pwd)/scripts:/build/scripts:ro,Z" -w /build/src/common {{CONTAINER_IMAGE}} /build/scripts/apply-zram.sh "{{KERNEL_VERSION}}"

# apply custom extra GKI patches
apply-extra-patches:
    {{PODMAN}} -v "$(pwd):/build/repo:ro,Z" -v "$(pwd)/src:/build/src:Z" -v "$(pwd)/scripts:/build/scripts:ro,Z" -w /build/src/common {{CONTAINER_IMAGE}} /build/scripts/apply-extra-patches.sh "{{KERNEL_VERSION}}"

# configure kernel defconfig and build flags
configure:
    {{PODMAN}} -v "$(pwd)/src:/build/src:Z" -v "$(pwd)/tmp:/build/tmp:ro,Z" -v "$(pwd)/scripts:/build/scripts:ro,Z" -w /build/src {{CONTAINER_IMAGE}} /build/scripts/configure.sh

# compile the kernel with bazel
build-kernel:
    {{PODMAN}} -v "$(pwd)/src:/build/src:Z" -v "$(pwd)/scripts:/build/scripts:ro,Z" -w /build/src {{CONTAINER_IMAGE}} /build/scripts/build-kernel.sh

# package anykernel3 zip with xz ramdisk compression
package:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p out/
    echo "==> locating kernel image..."
    IMAGE=$(find src/ -name "Image" -type f -path "*/kernel_aarch64/*" 2>/dev/null | head -1)
    if [[ -z "$IMAGE" ]]; then
        IMAGE=$(find src/ -name "Image" -type f 2>/dev/null | head -1)
    fi
    if [[ -z "$IMAGE" ]]; then
        echo "FATAL: kernel Image not found"
        exit 1
    fi
    echo "  -> found: $IMAGE"
    echo "==> preparing anykernel3 package..."
    STAGING="tmp/anykernel3-staging"
    rm -rf "$STAGING"
    cp -r tmp/anykernel3 "$STAGING"
    cp "$IMAGE" "$STAGING/Image"
    sed -i 's/^ramdisk_compression=.*/ramdisk_compression=lz4/' "$STAGING/anykernel.sh"
    sed -i 's/^kernel\.string=.*/kernel.string=GKI_KernelSU_SUSFS_ZeroMount/' "$STAGING/anykernel.sh"
    SUBLEVEL="{{SUB_LEVEL}}"
    if [[ -f src/common/Makefile ]]; then
        EXTRACTED=$(grep '^SUBLEVEL = ' src/common/Makefile | awk '{print $3}')
        [[ -n "$EXTRACTED" ]] && SUBLEVEL="$EXTRACTED"
    fi
    ZIP_NAME="{{ANDROID_VERSION}}-{{KERNEL_VERSION}}.${SUBLEVEL}-{{OS_PATCH_LEVEL}}-{{KSU_VARIANT}}-ZeroMount-AnyKernel3.zip"
    echo "==> creating ${ZIP_NAME}..."
    cd "$STAGING" && zip -r9 "../../out/${ZIP_NAME}" ./* && cd ../..
    echo "==> output: out/${ZIP_NAME}"
    ls -lh "out/${ZIP_NAME}"

# update dependency repos (pull latest changes)
update-deps:
    #!/usr/bin/env bash
    set -euo pipefail
    for r in tmp/action-build tmp/gki-config tmp/kernel_patches tmp/sukisu_patch tmp/super-builders tmp/susfs4ksu; do
        if [[ -d "$r/.git" ]]; then
            echo "==> updating $r..."
            git -C "$r" pull --ff-only || { git -C "$r" fetch && git -C "$r" reset --hard origin/HEAD; }
        fi
    done

# build for lts branch instead
build-lts:
    OS_PATCH_LEVEL=lts SUB_LEVEL=X just build-all
