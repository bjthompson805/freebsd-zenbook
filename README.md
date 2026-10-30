# mt7925

Native Wi-Fi for the MediaTek MT7925 on FreeBSD.

FreeBSD 15.1 already contains the Linux `mt76` driver, `mt7925` included,
under `sys/contrib/dev/mediatek/mt76`. It is compiled through LinuxKPI,
FreeBSD's in-kernel Linux driver layer (the same way `iwlwifi` and `amdgpu`
run), so this is not the Linuxulator and not a VM like `wifibox`. But it is
not built, and LinuxKPI is missing pieces it depends on, so the card stays
unattached:

    none1@pci0:195:0:0: class=0x028000 vendor=0x14c3 device=0x7925

These eight patches against `releng/15.1` fill those gaps. With them the
chip loads its firmware, scans, joins WPA2 networks and passes traffic.

## Status

| Chip   | PCI ID      | Machine                      | State    |
|--------|-------------|------------------------------|----------|
| MT7925 | `14c3:7925` | ASUS Zenbook S 16 (UM5606WA) | Verified |

Tested on FreeBSD 15.1, as a station on a 5 GHz WPA2 network (802.11ac,
80 MHz): DHCP, 6 ms pings to the access point, no loss. Loading, unloading,
and failed or lost connections no longer panic.

Not tested: 2.4 GHz and 6 GHz (no network was in range), suspend and
resume, access point and monitor modes, WPA3-only networks. Other mt76
chips (MT7921, MT7922) share most of this code and probably benefit from
the LinuxKPI fixes, but are untested. Please report back.

## The patches

| # | Fixes |
|---|-------|
| 1 | LinuxKPI's `page_pool` was all stubs returning NULL, so mt76 had no RX buffers. A minimal one hands out a page per buffer. Also implements `napi_build_skb()` and aliases `system_percpu_wq`. |
| 2 | `dmam_alloc_coherent()` kept a pointer to the caller's DMA handle and read it at detach, after it was freed: unloading panicked. |
| 3 | `dma_sync_single_for_device()` had `PREREAD` and `PREWRITE` swapped, so bounce pages never got the data. With a 32-bit DMA mask and more than 4 GB of RAM, the chip read empty MCU commands and never answered. |
| 4 | `SKB_WITH_OVERHEAD()` reserved room for `skb_shared_info` that LinuxKPI does not keep in the buffer, leaving 448 of 2048 bytes. Every larger frame, beacons included, was dropped, so scans came back empty. |
| 5 | Managed (`devm_`/`dmam_`) resources were freed after the DMA state they need. They are now released right after the driver's `remove()`, as in Linux. |
| 6 | A destroyed idr locked a destroyed mutex. mt7925 cleans a station up twice, so a failed connection panicked. |
| 7 | Adds the `compat.linuxkpi.mt7925_pci_runtime_pm` tunable (see below). |
| 8 | `idr_remove()` of an unused id panicked; Linux returns NULL, and mt76's TX status check relies on it. |

2 and 3 are fixed in FreeBSD main in the same way.

## Install

The patches change LinuxKPI code that is compiled into the kernel, so this
builds a kernel as well as the two modules. The kernel is installed to
`/boot/mt7925`, beside the stock one, which keeps pkgbase's `/boot/kernel`
untouched.

Get a `releng/15.1` source tree and patch it:

    git clone -b releng/15.1 --depth 1 https://git.freebsd.org/src.git /usr/src
    make patch

Build and install (`SRC` and `OBJ` default to `/usr/src` and
`/usr/obj/mt7925`):

    make
    make install

Install the firmware:

    pkg install wifi-firmware-mt76-kmod-mt7925

Add to `/boot/loader.conf`:

    kernel="mt7925"
    compat.linuxkpi.skb.mem_limit="1"
    compat.linuxkpi.mt7925_pci_runtime_pm="0"

and to `/etc/rc.conf`, adding to any `kld_list` you have:

    kld_list="mt76_core if_mt7925"
    wlans_mt79250="wlan0"
    ifconfig_wlan0="WPA DHCP"

Put your networks in `/etc/wpa_supplicant.conf` (`wpa_passphrase` prints a
block), then reboot. If the new kernel ever fails to boot, pick `kernel`
from the boot menu's kernel option to get the stock one back.

### The loader settings

- `compat.linuxkpi.skb.mem_limit="1"` allocates socket buffers below 4 GB.
  The chip uses 32-bit DMA, and busdma cannot bounce a buffer that spans
  two pages into the single segment LinuxKPI asks for, so firmware
  download fails with `-ENOMEM` without it. It only affects Wi-Fi drivers.
- `compat.linuxkpi.mt7925_pci_runtime_pm="0"` keeps the chip awake. With
  runtime PM (the default, as in Linux) it sleeps after about 80 ms idle and
  every packet after that waits for it: pings went from 6 ms to 8–60 ms.
  Leave it at `1` to save battery. It is read when the driver loads; Linux
  can switch it at runtime in debugfs, but doing that on a live connection
  drops the link under LinuxKPI.

## Updates

- `pkg upgrade` leaves `/boot/mt7925` and `/boot/modules` alone, so this
  keeps working. But a new base kernel package (a security patch such as
  15.1-p7) goes to `/boot/kernel`, which you are not booting: update the
  source tree, `make patch`, `make` and `make install` to pick it up.
- A new release (15.2, 16.0) needs these patches checked or redone: the
  driver and LinuxKPI change between releases, and some fixes are already
  in main. Don't move to one until this has been ported.

## Known issues

- A panic can leave the chip unable to start (`driver own failed` in
  `dmesg`). A reboot is not enough; power the machine off completely.
- net80211 sometimes asks for an AUTH to AUTH transition, which LinuxKPI
  does not support (`error 95`); the attempt is dropped and retried.
- The page pool does not recycle pages, and only works with 1:1 DMA
  mappings (no IOMMU, the FreeBSD default). Allocation fails with a warning
  otherwise.

## License

The patches modify FreeBSD's LinuxKPI (BSD-2-Clause) and mt76
(BSD-3-Clause-Clear) and are under the license of the file each changes.
The Makefile and this README are BSD-2-Clause, see `LICENSE`. The firmware
belongs to MediaTek, is distributed through linux-firmware and the FreeBSD
`wifi-firmware-mt76-kmod-mt7925` package under its own license, and is not
part of this repository.
