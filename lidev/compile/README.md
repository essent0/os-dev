# compile/

Run every command from this directory:

```bash
cd compile
```

The kernel source is `../linux`. Object files go in `build/`. Nothing below writes into the source tree.

## Change code, compile, boot

After you edit a file under `../linux`:

```bash
./build.sh
./boot.sh shell
```

`./build.sh` is an incremental compile. It produces `build/arch/x86/boot/bzImage`. The second run is much faster than the first.

`./boot.sh shell` boots that image in QEMU and leaves you at a root shell on the serial console. The shell is BusyBox. `poweroff -f` shuts the VM down and gives you the host prompt back. Exiting the shell does the same.

Plain `./boot.sh` does not leave you in Linux. It runs the `hello` experiment and powers off.

## What you can do in the shell

You are root in a tiny initramfs, not a full distro. Useful places:

```sh
uname -a
dmesg
cat /proc/version
ls /host/experiments
```

`/host` is this directory's `share/` folder, mounted from the host. Edit a script on the host and it is already visible in the guest. You do not rebuild the initramfs for that.

## Each script

### deps.sh

Checks for flex, bison, libelf headers, and qemu. If `sudo` works, it installs them. Otherwise it unpacks those packages under this directory and the other scripts find them. You already ran this once. Run it again only if a tool goes missing.

### configure.sh

Writes `build/.config`.

```bash
./configure.sh            # does nothing if build/.config already exists
./configure.sh --reconfig # rebuild the config from scratch
```

The config is `x86_64_defconfig`, plus the kernel's `kvm_guest.config`, plus `config/qemu.fragment`. Edit the fragment when you want a kernel option, then `--reconfig`, then `./build.sh`.

### build.sh

Compiles the kernel into `build/`.

```bash
./build.sh                # bzImage
./build.sh vmlinux        # stop after vmlinux
./build.sh -j8 bzImage    # extra make arguments are passed through
```

`vmlinux` (for gdb or addr2line) is `build/vmlinux`. Debug info is off. Turn it on in `config/qemu.fragment` if you need it.

### initramfs.sh

Packs BusyBox and `guest/init` into `initramfs.cpio.gz`. The image is already built. Run this again only if you change `guest/init`. Kernel edits do not need a new initramfs.

### boot.sh

Boots `build/arch/x86/boot/bzImage` in QEMU.

```bash
./boot.sh shell           # stay in Linux until you power off
./boot.sh                 # run share/experiments/hello, then power off
./boot.sh dmesg           # run share/experiments/dmesg, then power off
./boot.sh hello,dmesg     # both, one boot
./boot.sh kselftest       # run tests already installed by kselftest.sh
```

Serial output is also saved in `logs/<timestamp>/serial.log`. `logs/latest` points at the newest run.

The one-shot modes (`./boot.sh`, `./boot.sh dmesg`, kselftest) power the VM off when they finish. `./boot.sh shell` waits.

### experiment.sh

Same boot as `boot.sh`, then a short pass/fail summary.

```bash
./experiment.sh list
./experiment.sh hello
./experiment.sh dmesg
./experiment.sh hello,dmesg
./experiment.sh build probe
```

`build` compiles `share/experiments/src/<name>.c` as a static binary, drops it in `share/experiments/`, and boots it. `share/experiments/src/probe.c` is the example.

### kselftest.sh

Builds kernel selftests and runs them inside the guest, against this bzImage.

```bash
./kselftest.sh            # default: size and proc
./kselftest.sh build      # compile and install only
./kselftest.sh run        # boot tests already installed
./kselftest.sh rebuild    # install again even if the target list did not change
./kselftest.sh proc       # just that directory
```

Installed tests land in `share/kselftest/`.

### analyze.sh

Reads a serial log and prints boot, experiment, and kselftest results.

```bash
./analyze.sh                          # logs/latest/serial.log
./analyze.sh logs/latest/serial.log
```

`experiment.sh` and `kselftest.sh` already call this. Use it yourself after `./boot.sh`.

### cycle.sh

Runs the whole loop: deps, configure if needed, build, initramfs, one experiment, then the default kselftests.

```bash
./cycle.sh                 # experiment hello, then kselftests
./cycle.sh dmesg           # experiment dmesg, then kselftests
./cycle.sh --reconfig      # regenerate .config first
./cycle.sh help
```

## Other files

| Path | Role |
|---|---|
| `config/qemu.fragment` | Kernel options merged into `.config`. Edit, then `./configure.sh --reconfig`. |
| `guest/init` | PID 1 inside the VM. Rebuild the initramfs after changing it. |
| `share/experiments/` | Programs the guest runs. Shell scripts or static binaries. |
| `share/experiments/src/` | C sources for `./experiment.sh build`. |
| `share/kselftest/` | Installed selftests. |
| `share/results/` | For anything the guest writes back to the host. |
| `logs/` | One directory per boot. `logs/latest` is the newest. |
| `build/` | Kernel build tree. `bzImage` is `build/arch/x86/boot/bzImage`. |
| `env.sh`, `lib/` | Shared helpers. The scripts source these. Don't run them yourself. |

## Knobs

Set these in the environment when you want something other than the default.

| Variable | Default | Effect |
|---|---|---|
| `JOBS` | all CPUs | `make -j` for `./build.sh` |
| `MEM` | `2048` | guest RAM in MB |
| `SMP` | `2` | guest CPUs |
| `TIMEOUT` | `120` (600 for kselftest) | seconds before a one-shot boot is killed |
| `QEMU_EXTRA` | empty | extra words appended to the qemu command |
| `TARGETS` | `size proc` | kselftest directories, if you don't pass them as arguments |
