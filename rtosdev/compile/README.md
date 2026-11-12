# compile/

Run every command from this directory:

```bash
cd compile
```

The kernel source is `../FreeRTOS-Kernel`. Object files go in `build/`. Nothing here writes into the kernel tree.

The guest is a Cortex-M3 image for QEMU's `mps2-an385` board (25 MHz SysTick, CMSDK UART0 at `0x40004000`). `build/freertos.elf` is what QEMU boots.

## Change code, compile, boot

After you edit a file under `../FreeRTOS-Kernel`, or a file under `guest/` or `share/experiments/src/`:

```bash
./build.sh
./boot.sh
```

`./build.sh` is incremental. The first run is a full compile. Later runs rebuild what changed and relink.

`./boot.sh` runs the `hello` experiment and powers the VM off. `./boot.sh shell` leaves you at a UART prompt. `poweroff` (or Ctrl-C) gives you the host prompt back.

## Each script

### deps.sh

Checks for `arm-none-eabi-gcc`, `qemu-system-arm`, and `gdb-multiarch`. If `sudo` works, it installs them. Otherwise it downloads the Ubuntu packages under this directory and the other scripts see them through a user namespace. Run it again only if a tool goes missing.

### build.sh

```bash
./build.sh
./build.sh clean
./build.sh -j4
```

The image is `build/freertos.elf`. `build/freertos.map` is the linker map. Debug info is on (`-Og -g3`).

### boot.sh

```bash
./boot.sh                 # hello, then power off
./boot.sh ping            # queue ping-pong between two tasks
./boot.sh hello,ping      # both, one boot
./boot.sh tasks           # print the task list
./boot.sh shell           # UART shell until poweroff or Ctrl-C
./boot.sh run             # print a tick once a second until Ctrl-C
```

Serial output is also saved in `logs/<timestamp>/serial.log`. `logs/latest` points at the newest run.

`TIMEOUT` (default 30) bounds the one-shot modes. Shell and `run` do not time out.

### experiment.sh

Same boot as `boot.sh`, after a rebuild, then a pass/fail line.

```bash
./experiment.sh
./experiment.sh ping
./experiment.sh hello,ping
./experiment.sh list
./experiment.sh build myexp
```

`build` checks that `share/experiments/src/<name>.c` exists, rebuilds, and boots it. The source is linked into the image. There is no separate host binary.

### analyze.sh

Reads `logs/latest/serial.log` and prints one line per `RTOSDEV_END` marker.

### debug.sh

```bash
./debug.sh                # QEMU halted, gdb stopped at main
./debug.sh qemu           # guest shell on this terminal, gdb stub on :1234
./debug.sh attach         # gdb, for a stub that is already up
```

In gdb, `rtos-current` prints the running task once the scheduler has started. `rtos-faults` breaks on a hard fault, `configASSERT`, a stack overflow, and a failed heap allocation. Those commands are in `gdb/freertos.gdb`.

`./debug.sh` writes the UART to the serial log, because gdb owns the terminal. `./debug.sh qemu` is the one that leaves the shell on this terminal; attach gdb from another terminal.

`GDB_PORT` defaults to 1234.

### cycle.sh

`deps.sh`, `build.sh`, then `hello` and `ping` in one boot.

## Add an experiment

Put `share/experiments/src/NAME.c` next to `hello.c`. Export one function and register it:

```c
#include "experiment.h"

static int myexp_run(void) {
    rtosdev_printf("myexp ran\n");
    return 0;
}

RTOSDEV_EXPERIMENT(myexp, myexp_run);
```

Return 0 for pass. Then:

```bash
./experiment.sh myexp
```

From the shell, `experiments` lists names and `run myexp` runs one without leaving the shell.

## Shell

`./boot.sh shell` starts a small command line on the UART:

```text
help version tasks heap uptime experiments run poweroff
```

The host terminal is in cooked mode, so it echoes what you type. The guest does not echo again.

## Do not

- Do not build inside `FreeRTOS-Kernel/`. Objects stay in `compile/build/`.
- Do not boot a raw `.bin`. QEMU loads the ELF, and initialized data is placed in RAM by the loader.
- Do not turn on a heavy tracing library unless you mean to. The image is the kernel, `heap_4`, and this board package.
