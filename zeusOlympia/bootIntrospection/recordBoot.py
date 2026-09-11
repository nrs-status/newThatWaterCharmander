"""Record a boot attempt or boot success to persistent storage.

Called by the `record-boot-attempt` and `record-boot-success` systemd
services (see default.nix). The kind of record is passed as the single
command-line argument:

    record-boot attempt   # as early as possible in stage 2
    record-boot success   # only once sshd is up (machine is remotely usable)

Each run appends one line to /persist/boot-introspection/boots.log,
of the form:

    2025-09-11T01:20:00+02:00 attempt boot_id=<uuid> kernel=<release>
                              generation=<store path>

A boot attempt with no matching success line is a boot that failed to
reach a usable post-boot state.
"""

import datetime
import os
import pathlib
import sys

LOG_DIR = pathlib.Path("/persist/boot-introspection")
LOG_FILE = LOG_DIR / "boots.log"


def boot_id() -> str:
    """Kernel-provided UUID identifying the current boot."""
    return pathlib.Path("/proc/sys/kernel/random/boot_id").read_text().strip()


def generation() -> str:
    """Path of the current system generation, or 'unknown'."""
    try:
        return str(pathlib.Path("/run/current-system").resolve())
    except OSError:
        return "unknown"


def main() -> None:
    if len(sys.argv) != 2 or sys.argv[1] not in ("attempt", "success"):
        print("usage: record-boot <attempt|success>", file=sys.stderr)
        sys.exit(1)
    kind = sys.argv[1]
    now = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    line = (
        f"{now} {kind} boot_id={boot_id()} kernel={os.uname().release}"
        f" generation={generation()}\n"
    )
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    with LOG_FILE.open("a") as log:
        log.write(line)


if __name__ == "__main__":
    main()
