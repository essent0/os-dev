# compile/

Run every command from this directory:

```bash
cd compile
```

The source tree is `../xv6-public` (x86 xv6). `./build.sh` rsyncs it into `build/tree` and runs make there. Nothing here writes into `xv6-public`.

Edit files under `../xv6-public`, then `./build.sh` again. The copy is rebuilt. Do not edit `build/tree`; the next build overwrites it.

## Change code, compile, boot

```bash
./build.sh
./boot.sh
```

`./boot.sh` boots xv6, runs `echo` from the shell, and kills QEMU. `./boot.sh shell` leaves you at the `$` prompt. Ctrl-A X quits QEMU (`-nographic` takes the terminal, so Ctrl-C does not).

## Each script

### deps.sh

Checks for `qemu-system-i386`, `gcc -m32`, `gdb`, `perl`, `python3`, and `make`. If `sudo` works, it installs what is missing. Otherwise it downloads the Ubuntu packages under this directory and the other scripts see them through a user namespace. Run it again only if a tool goes missing.

### build.sh

```bash
./build.sh
./build.sh clean
```

Images are `build/tree/xv6.img`, `build/tree/fs.img`, and `build/tree/kernel`. Make runs with `-j1` because the xv6 makefile is not safe to parallelize.

The build copy drops `-Werror`. gcc treats an array-bounds warning in `mp.c` as an error, and the stock makefile will not finish. `xv6-public/Makefile` is unchanged.

### boot.sh

```bash
./boot.sh                 # echo UDEV_END hello status=0
./boot.sh ls              # ls, then the marker
./boot.sh cat             # cat README
./boot.sh 'grep hello README'
./boot.sh usertests       # long; TIMEOUT defaults to 240
./boot.sh shell           # interactive, until Ctrl-A X
```

Each boot copies the disk images into `logs/<timestamp>/`, so a guest that writes the filesystem does not change `build/tree/fs.img`. `logs/latest` points at the newest run.

`TIMEOUT` bounds one-shot boots (default 20). The shell does not time out. `CPUS` defaults to 1. `ACCEL` defaults to `tcg` (`ACCEL=kvm` if you want KVM). `QEMU_EXTRA` is split on spaces and appended to the qemu command.

### experiment.sh

Same boot as `boot.sh`, after a rebuild, then a pass/fail line.

```bash
./experiment.sh
./experiment.sh ls
./experiment.sh list
```

`list` prints `hello`, `ls`, `cat`, and `usertests`. Any other argument is a shell command.

### analyze.sh

Reads `logs/latest/serial.log`. A one-shot passes when the log contains `init: starting sh` and `UDEV_END <name> status=0`, and does not contain `panic:` or `exec ... failed`.

### debug.sh

```bash
./debug.sh                # QEMU halted, gdb stopped at kernel main
./debug.sh qemu           # xv6 shell on this terminal, gdb stub on :1234
./debug.sh attach         # gdb, for a stub that is already up
./debug.sh batch          # break at main, backtrace, quit
```

`GDB_PORT` defaults to 1234. `gdb/xv6.gdb` switches between i8086 and i386 the way `xv6-public/.gdbinit.tmpl` does. Symbols come from `build/tree/kernel`.

### cycle.sh

```bash
./cycle.sh                # deps, build, hello, ls
./cycle.sh usertests
```

## Guest contract

The shell prompt is `$ `, printed by `sh`. `init` prints `init: starting sh` before it execs the shell. A one-shot types commands after that prompt, then `echo UDEV_END <name> status=0`, and waits until the shell prompts again. xv6 has no poweroff syscall, so the script kills QEMU.

`usertests` prints `usertests starting` and a line of `ok` per test. The last test replaces itself with `echo ALL TESTS PASSED`. The marker after the shell prompts again is the pass signal. Each boot gets a fresh `fs.img`, so `usertests.ran` does not carry over to the next run.
