#!/bin/bash
# Build the 6.19 sunxi NAND driver as out-of-tree modules against a running
# 6.12 Armbian kernel. No kernel rebuild, no backport patches needed.
#
# Put the 6.19 drivers/mtd/nand tree under ./drivers/mtd/nand first.
set -u
KSRC=/usr/src/linux-headers-$(uname -r)
BASE=$(dirname "$0")/drivers/mtd/nand

echo "===== pass 1: nandcore ====="
make -C "$KSRC" M="$BASE" \
  KCPPFLAGS="-DCONFIG_DEBUG_INFO_BTF_MODULES -DCONFIG_MTD_NAND_CORE=1" modules 2>&1 | tail -15

echo "===== pass 2: rawnand + sunxi_nand ====="
make -C "$KSRC" M="$BASE/raw" \
  KBUILD_EXTRA_SYMBOLS="$BASE/Module.symvers" \
  KCPPFLAGS="-DCONFIG_DEBUG_INFO_BTF_MODULES -DCONFIG_MTD_RAW_NAND=1" modules 2>&1 | tail -20

echo "===== result ====="
for m in nandcore nand sunxi_nand; do
  p=$(find "$(dirname "$0")" -name "$m.ko" 2>/dev/null | head -1)
  [ -n "$p" ] && echo "ok      $m.ko" || echo "MISSING $m.ko"
done
