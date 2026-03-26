#!/bin/bash
set -euo pipefail

ANDROID_VERSION="$1"
KERNEL_VERSION="$2"

# zeromount patch is identical across ksu variants
PATCH="/build/tmp/super-builders/android15-6.6/KernelSU-Next/patches/60_zeromount-${ANDROID_VERSION}-${KERNEL_VERSION}.patch"

echo "==> applying zeromount patch..."
patch -p1 -F3 --no-backup-if-mismatch < "$PATCH"

# fix: upstream zeromount patch has a bug where the goto zm_out in readdir.c
# is unconditional, skipping the buf.prev_reclen block that computes the
# actual return value. this makes every getdents return 0 ("no entries"),
# breaking all directory listings and causing boot failure.
echo "==> applying zeromount readdir fix..."
FIX="/build/repo/patches/fix-zeromount-readdir.patch"
#FIX="/home/wh/GKI_KernelSU_SUSFS_ZeroMount/patches/fix-zeromount-readdir.patch"
if [[ -f "$FIX" ]]; then
    patch -p1 -F3 --no-backup-if-mismatch < "$FIX"
else
    echo "WARNING: fix patch not found at $FIX, applying inline fix..."
    # fix all three getdents variants: move goto zm_out inside the brace
    sed -i '/zeromount_inject_dents\(64\)\?(/,/goto zm_out;/{
        /if (count != initial_count)/{
            N
            s/\(if (count != initial_count)\)\n\t\t\t\(error = initial_count - count;\)/\1 {\n\t\t\t\2/
        }
        /goto zm_out;/{
            s/\t\tgoto zm_out;/\t\t\tgoto zm_out;\n\t\t}/
        }
    }' fs/readdir.c
fi

# fix: zeromount_stat_hook dereferences filename->name without checking
# IS_ERR(filename). vfs_statx can be called with ERR_PTR(-ENOENT) from
# getname_flags, causing a kernel oops at vfs_statx+0x6c.
#echo "==> applying zeromount stat ERR_PTR fix..."
#FIX_STAT="/build/repo/patches/fix-zeromount-stat-errptr.patch"
#    patch -p1 -F3 --no-backup-if-mismatch < "$FIX_STAT"
#else#
#fi

echo "==> zeromount applied"
