# dummydev
A new device the guest can drive on this tree. QEMU is `qemudev/qemu`, branch `dummy`, tag `v9.2.0`. The board `rtosdev` boots is `mps2-an385` (`hw/arm/mps2.c`): Cortex-M3, fixed physical addresses, NVIC IRQs. That board has no PCI bus and does not publish these peripherals in a device tree. The guest finds the device because `mps2.c` maps the MMIO window and connects one IRQ.
Copy the shape of `mps2-fpgaio`, which is already on this board:
- `hw/misc/mps2-fpgaio.c`
- `include/hw/misc/mps2-fpgaio.h`
- created in `hw/arm/mps2.c` and mapped at `0x40028000`
`hw/misc/unimp.c` and `include/hw/misc/unimp.h` are the smaller sysbus skeleton (registers plus `type_init`, no board wiring).
## Add
| File | Role |
| --- | --- |
| `hw/misc/dummydev.c` | Device. `MemoryRegionOps` read/write, `sysbus_init_mmio`, `sysbus_init_irq`, realize, `TypeInfo` parent `TYPE_SYS_BUS_DEVICE`, `type_init`. |
| `include/hw/misc/dummydev.h` | `TYPE_DUMMYDEV`, state struct (`SysBusDevice` parent, `MemoryRegion`, `qemu_irq`). |
## Edit
| File | Change |
| --- | --- |
| `hw/misc/Kconfig` | `config DUMMYDEV` / `bool`. Same form as `config MPS2_FPGAIO` in this file. |
| `hw/misc/meson.build` | `system_ss.add(when: 'CONFIG_DUMMYDEV', if_true: files('dummydev.c'))`. Same form as the `CONFIG_MPS2_FPGAIO` line. |
| `hw/arm/Kconfig` | Under `config MPS2`, add `select DUMMYDEV`. `MPS2` is already `default y` for `arm-softmmu`, so the arm build picks the device up. |
| `hw/arm/mps2.c` | Include the header. In `mps2_common_init`, for `FPGA_AN385`, create the device, `sysbus_realize`, `sysbus_mmio_map`, `sysbus_connect_irq` into `qdev_get_gpio_in(armv7m, irq)`. Add a field on `MPS2MachineState` if you use `object_initialize_child` the way `fpgaio` does. |
`mps2.c` already covers the peripheral space with `create_unimplemented_device` (from `0x40000000`). A real mapping in that window replaces the stub for the bytes it owns. The comment above those calls says so.
IRQ lines `mps2_common_init` already connects on AN385: `0`–`5` and `18`–`21` (UARTs), `8`–`9` (timers), `10` (dual timer), `11` and `24` (SPI), `12` (UART overflow), `13` (ethernet), `22` (ADC). The watchdog uses the NMI line, not a numbered GPIO. Pick an address and an IRQ that this function does not already use.
## Do not edit
- `configs/devices/arm-softmmu/default.mak` — `CONFIG_MPS2` is already on. The `select DUMMYDEV` above is what links the device into `qemu-system-arm`.
- `qapi/` — only if the device grows a QMP command.
- `hw/arm/virt.c` and any FDT builder — `mps2-an385` does not describe FPGA peripherals in a device tree.
- PCI device files (`hw/misc/edu.c` and the rest) — nothing on this board enumerates PCI, so `-device` cannot attach it.
## Optional
- `hw/misc/trace-events` — one trace line if you want reads and writes in the QEMU log.
- A qtest under `tests/qtest/` — not required for the guest to see the device.
After those four edits and the two new files, rebuild with `qemudev/compile/build.sh`. The guest driver uses the physical address and the NVIC IRQ chosen in `hw/arm/mps2.c`.
