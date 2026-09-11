"""`boot-introspect`: interactive helper to diagnose a failed boot.

Prints the persistent boots.log, the journald boot list, and highlights
boot attempts that have no matching success record (i.e. failed boots).
See default.nix for the overall introspection workflow.
"""

import pathlib
import subprocess
import sys

LOG = pathlib.Path("/persist/boot-introspection/boots.log")


def recorded_boots():
    """Return (attempts, successes) boot_id sets parsed from boots.log."""
    attempts, successes = set(), set()
    if not LOG.is_file():
        return attempts, successes
    for line in LOG.read_text().splitlines():
        parts = line.split()
        if len(parts) < 4 or not parts[2].startswith("boot_id="):
            continue
        kind, boot_id = parts[1], parts[2].removeprefix("boot_id=")
        if kind == "attempt":
            attempts.add(boot_id)
        elif kind == "success":
            successes.add(boot_id)
    return attempts, successes


def main() -> None:
    print(f"== recorded boots ({LOG}) ==")
    if LOG.is_file():
        print(LOG.read_text(), end="")
    else:
        print("(no record found)")
    print()

    print("== journald boots ==")
    subprocess.run(["journalctl", "--list-boots"])
    print()

    print("== boot attempts without matching success (failed boots) ==")
    attempts, successes = recorded_boots()
    failed = sorted(attempts - successes)
    if not attempts:
        print("  (no record found)")
    elif failed:
        for boot_id in failed:
            print(f"  {boot_id}   (inspect with: journalctl --boot={boot_id})")
    else:
        print("  (none)")
    print()

    print(
        "old pre-rollback roots (kept 30d) are btrfs subvolumes under"
        " old_roots on <dedicated volume>"
    )


if __name__ == "__main__":
    sys.exit(main())
