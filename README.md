# H616 + SV6256P: Ethernet and internal WiFi at the same time

Notes from getting a HIBOX1644_V3.0 Android TV box (Allwinner H616, SV6256P WiFi)
to run Armbian/Ubuntu with **both** the internal WiFi and the Ethernet port
working. Every thread I could find on this ends with people picking one or the
other, so I'm writing down what actually fixed it.

Board is silkscreened `HIBOX1644_V3.0`, IK316-H / H316 family. The fix should
apply to any H616/H313 box with an SSV6x5x-family chip (SV6256P, SV6355P) running
a stock Armbian kernel.

Tested on:

```
Armbian, kernel 6.12.11-edge-sunxi64 (stock, from apt.armbian.com)
Ubuntu 24.04 noble rootfs
ssv6x5x driver from cdhigh/armbian_sv6256p
```

The two fixes below are not version specific, but the exact byte sizes I quote
further down are from this kernel.

## The problem

The out-of-tree ssv6x5x driver will not load against a stock Armbian kernel:

```
# insmod ssv6x5x.ko
insmod: ERROR: could not insert module ssv6x5x.ko: Invalid module format
# dmesg | tail -1
ssv6x5x: .gnu.linkonce.this_module section size must match struct module size
```

The common workaround is to rebuild the kernel with the driver built in. That
does get WiFi working and it is what most guides do. On this board it also breaks
Ethernet: with the custom kernel the RMII PHY comes up at zero and `end0` never
links. So you end up with WiFi or Ethernet, never both.

I went down the custom-kernel road first and burned about two days on the PHY
before giving up on it. The answer was to go back to the stock kernel and fix the
module instead.

## Two root causes. Both have to be fixed

Fixing one and not the other gets you nothing, which is most of why this took so
long to pin down.

### 1. The driver's own build flags kill ftrace instrumentation

`config_common.mak`, line 30:

```make
ccflags-y += -fpatchable-function-entry=0
```

On arm64 the kernel builds modules with `-fpatchable-function-entry=4,2`. The
driver's `=0` overrides it, so the module ends up with no
`__patchable_function_entries` section at all. The loader compares that against
the kernel's ftrace state and rejects the module.

Comment it out and let the kernel's flag win:

```make
# DISABLED (root cause of insmod failure): ccflags-y += -fpatchable-function-entry=0
```

### 2. `struct module` is not the size the headers claim

This one is not driver specific and is worth knowing if you build any
out-of-tree module on Armbian.

The running kernel was built with `CONFIG_DEBUG_INFO_BTF_MODULES=y`, which adds
`btf_data` pointers to `struct module` (+24 bytes here). The `.config` sitting in
`/usr/src/linux-headers-*` had it **off**, so the module compiles against a
smaller `struct module` than the running kernel actually has, the sizes disagree,
and you get the `this_module section size` message above.

To be clear about where that came from, because I got this wrong at first and
blamed the distro: the Armbian package was fine. I had regenerated the headers
myself in an environment with no pahole installed, and Kconfig quietly turns
`DEBUG_INFO_BTF` off when pahole is missing. `dpkg -V` says it plainly:

```
$ dpkg -V linux-headers-edge-sunxi64
??5??????   /usr/src/linux-headers-6.12.11-edge-sunxi64/.config
??5??????   /usr/src/linux-headers-6.12.11-edge-sunxi64/include/config/auto.conf
??5??????   /usr/src/linux-headers-6.12.11-edge-sunxi64/include/generated/autoconf.h
```

Those are exactly the files `make prepare` / `oldconfig` rewrites. If yours comes
back clean, your headers are untouched and your problem is somewhere else.

So the general lesson isn't "Armbian ships bad headers", it's that **the headers'
`.config` can drift from the kernel you are actually running**, and when it does
the module loader's complaint tells you nothing useful about why. Compare them
directly before assuming anything:

```bash
diff <(zcat /proc/config.gz) /usr/src/linux-headers-"$(uname -r)"/.config
```

Force the define back on at build time. No kernel rebuild needed:

```
KCPPFLAGS="-DCONFIG_DEBUG_INFO_BTF_MODULES"
```

## Building

Native on the box, against the stock headers:

```bash
git clone https://github.com/cdhigh/armbian_sv6256p
cd armbian_sv6256p
patch -p1 < /path/to/patches/0001-drop-fpatchable-function-entry-0.patch
make clean
make -j"$(nproc)" \
  KSRC=/usr/src/linux-headers-"$(uname -r)" \
  ARCH=arm64 \
  KCPPFLAGS="-DCONFIG_DEBUG_INFO_BTF_MODULES"
```

Check the result before installing it:

```bash
readelf -SW ssv6x5x.ko | grep -c patchable   # must be 2, not 0
readelf -SW ssv6x5x.ko | grep this_module    # size should be 0x500 (1280)
```

`patchable` still 0 means cause 1 is not fixed. `this_module` at 0x4e8 (1256)
instead of 0x500 means cause 2 is not fixed. Your numbers will differ on a
different kernel version, the point is that they have to match what the running
kernel has.

Install:

```bash
sudo cp ssv6x5x.ko /lib/modules/"$(uname -r)"/kernel/drivers/net/wireless/ssv6256p/
sudo depmod "$(uname -r)"
echo ssv6x5x | sudo tee /etc/modules-load.d/ssv6x5x.conf
```

Firmware (`ssv6x5x-wifi.cfg`, `ssv6x5x-sw.bin`) goes in `/lib/firmware/`. It is
not in this repo, the licence on those blobs is unclear to me. Take them from the
driver repo linked above, or pull them off your own box's Android partition.

## Ethernet, separately

Nothing exotic here, `dwmac_sun8i` handles it. The one gotcha on this board is
that the RMII PHY needs roughly 9 seconds after a cold boot before it will accept
a link. If anything brings `end0` up before that, `phylink_validate` returns
`-EINVAL`, the recovery path pins the link at 10 Mbps half duplex, and it stays
there until you reboot.

`systemd/` has a one-shot unit that waits until uptime is at least 12 seconds and
then brings the interface up for the first time. A flat `sleep 60` works too,
this just gets you online about eight times sooner.

I don't think this is the correct fix. The correct fix is probably a reset delay
property on the PHY node. I stopped chasing it once the box was up.

## Result

```
# lsmod | grep -E 'ssv|dwmac'
ssv6x5x               602112  0
mac80211             1179648  1 ssv6x5x
cfg80211             1007616  2 ssv6x5x,mac80211
dwmac_sun8i            28672  0

# ip -br link
end0    UP  xx:xx:xx:xx:xx:xx <BROADCAST,MULTICAST,UP,LOWER_UP>
wlan0   UP  xx:xx:xx:xx:xx:xx <BROADCAST,MULTICAST,UP,LOWER_UP>
```

Both up at once, survives cold boots.

## Also: the internal NAND is reachable

Separate finding, written up in [nand/](nand/). Short version, the "H616 NAND is
not supported in mainline" answer you will find everywhere is out of date as of
6.19, and you can get to it as `/dev/mtd0` without rebuilding your kernel.

## Credits

- [cdhigh/armbian_sv6256p](https://github.com/cdhigh/armbian_sv6256p) for the
  ssv6x5x driver tree this is built from.
- The Armbian Tanix TX6s-AXP313 image, whose kernel, dtb and U-Boot I used as a
  known-good base after my own kernel turned out to be a dead end.
- Richard Genoud's sunxi NAND work that landed in 6.19.
