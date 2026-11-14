#!/usr/bin/env python3
"""Boot xv6 and type shell lines once the '$ ' prompt is up.

One-shot runs have no poweroff syscall. This waits until the shell has
printed a prompt for every line, then terminates QEMU. Exit 124 on timeout.
"""
import argparse
import os
import select
import shlex
import signal
import shutil
import subprocess
import sys
import time


def prompt_count(buf: bytes) -> int:
    # sh prints "$ " when it is ready for a line. The '$' is not always
    # at the start of a line: cat leaves the cursor mid-line when the
    # file has no trailing newline, and the next prompt is glued on.
    # A command whose own output contains "$ " will look like an extra prompt.
    return buf.replace(b"\r", b"").count(b"$ ")


def kill_qemu(proc: subprocess.Popen) -> None:
    if proc.poll() is not None:
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.wait(timeout=2)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--timeout", type=float, required=True)
    ap.add_argument("--log", required=True)
    ap.add_argument("--fs", required=True)
    ap.add_argument("--xv6", required=True)
    ap.add_argument("--smp", default=os.environ.get("CPUS", "1"))
    ap.add_argument("--mem", default=os.environ.get("MEM", "512"))
    ap.add_argument("--accel", default=os.environ.get("ACCEL", "tcg"))
    ap.add_argument("--line", action="append", required=True)
    args = ap.parse_args()

    qemu = shutil.which("qemu-system-i386")
    if not qemu:
        print(
            "qemu-system-i386 is not available. Run deps.sh",
            file=sys.stderr,
        )
        return 1

    cmd = []
    if shutil.which("stdbuf"):
        cmd += ["stdbuf", "-oL", "-eL"]
    cmd += [
        qemu,
        "-machine", f"pc,accel={args.accel}",
        "-display", "none",
        "-monitor", "none",
        "-serial", "stdio",
        "-no-reboot",
        "-nic", "none",
        "-drive", f"file={args.fs},index=1,media=disk,format=raw",
        "-drive", f"file={args.xv6},index=0,media=disk,format=raw",
        "-smp", str(args.smp),
        "-m", str(args.mem),
    ]
    extra = os.environ.get("QEMU_EXTRA", "")
    if extra:
        cmd += shlex.split(extra)

    proc = subprocess.Popen(
        cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    assert proc.stdin is not None and proc.stdout is not None
    os.set_blocking(proc.stdin.fileno(), False)
    os.set_blocking(proc.stdout.fileno(), False)

    lines = [ln.encode() + b"\n" for ln in args.line]
    pending = b""
    sent = 0
    buf = b""
    saw_end = False
    deadline = time.monotonic() + args.timeout
    log = open(args.log, "wb")

    def note(msg: bytes) -> None:
        log.write(msg)
        log.flush()
        sys.stdout.buffer.write(msg)
        sys.stdout.buffer.flush()

    try:
        while True:
            if time.monotonic() > deadline:
                note(b"\nqemu timed out\n")
                kill_qemu(proc)
                return 124

            # A new '$ ' means the shell is inside gets() and will take a line.
            if not pending and sent < len(lines) and prompt_count(buf) > sent:
                pending = lines[sent]
                sent += 1

            rset = [proc.stdout]
            wset = [proc.stdin] if pending else []
            readable, writable, _ = select.select(rset, wset, [], 0.2)

            if proc.stdout in readable:
                try:
                    chunk = os.read(proc.stdout.fileno(), 4096)
                except BlockingIOError:
                    chunk = b""
                if chunk == b"" and proc.poll() is not None:
                    break
                if chunk:
                    log.write(chunk)
                    log.flush()
                    sys.stdout.buffer.write(chunk)
                    sys.stdout.buffer.flush()
                    buf += chunk
                    if b"UDEV_END " in buf:
                        saw_end = True

            if proc.stdin in writable and pending:
                try:
                    n = os.write(proc.stdin.fileno(), pending[:32])
                except BlockingIOError:
                    n = 0
                except BrokenPipeError:
                    pending = b""
                    break
                pending = pending[n:]

            if (
                saw_end
                and sent == len(lines)
                and not pending
                and prompt_count(buf) > len(lines)
            ):
                break
            if proc.poll() is not None:
                break
    finally:
        kill_qemu(proc)
        log.close()

    if saw_end and sent == len(lines):
        return 0
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
