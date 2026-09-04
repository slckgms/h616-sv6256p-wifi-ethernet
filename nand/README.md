# Reaching the internal NAND on an H616 box

If you search for this you will find a lot of "the internal storage on H616
boxes is not supported in mainline, use an SD card". That was true and it is not
any more. Richard Genoud's H6/H616 NAND controller driver went into Linux 6.19
as `CONFIG_MTD_NAND_SUNXI`.

I got the chip visible as `/dev/mtd0` on a HIBOX1644_V3.0 without rebuilding my
kernel, by compiling the 6.19 driver as out-of-tree modules against a running
6.12.11 Armbian kernel. No backport patches were needed, the driver builds
against 6.12 as is.

## What's in there

```
Micron 16GB MLC NAND, FxxL05B128G1KDBABJ4, ID 0x2c 0x84
16384 MiB, 8 MB erase blocks, 16 KB pages, 2208 bytes OOB
```

## The mmc2 red herring

Before any of this, the device tree had a `mmc2` controller at `0x4022000`
declared as a non-removable card that never probed anything. I spent a while
assuming there was a dead eMMC on the board.

There isn't. Those pins belong to the NAND controller. `mmc2` was holding them
through pinctrl, which is why NAND never probed. Unbind it and the pins come
free:

```bash
echo 4022000.mmc > /sys/bus/platform/drivers/sunxi-mmc/unbind
```

## Building and loading

`build-nand-modules.sh` builds it in two passes, `nandcore` first, then
`rawnand` + `sunxi_nand` against the symbols from pass one. Note the
`-DCONFIG_DEBUG_INFO_BTF_MODULES` in there, it is the same `struct module` size
problem described in the top-level README and it applies to every out-of-tree
module on this install, not just the WiFi driver.

```bash
insmod nandcore.ko
insmod nand.ko
insmod sunxi_nand.ko
echo 4022000.mmc > /sys/bus/platform/drivers/sunxi-mmc/unbind
mkdir /sys/kernel/config/device-tree/overlays/nand
cat nand-h616-pio.dtbo > /sys/kernel/config/device-tree/overlays/nand/dtbo
```

Use the PIO overlay in this directory, the one with no `dmas` property. I also
tried it with DMA wired up and the controller just gives interrupt timeouts,
see below.

## What still doesn't work

**DMA.** The 6.19 driver's own patch notes say DMA/MDMA is not included for
H616 yet. Without it you fall back to PIO, and PIO reads at about 176 kB/s.
Fine for dumping a partition and reading it back, useless for running a rootfs.

**Booting from it.** That needs U-Boot SPL NAND support for H616
(BROM to boot0 to U-Boot to kernel) and I don't believe mainline has it. MLC
plus whatever scrambling the vendor boot0 uses makes that a real project on its
own.

**Writing.** Untested. The box still has its original Android install on that
NAND and I wasn't willing to erase it to find out. If you try it, do it on a box
you don't mind bricking.

So NAND is readable, but an SD card is still required to boot. Getting past that
means solving the DMA speed and the U-Boot side.
