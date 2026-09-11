# Boot introspection and log persistence for lanchamarcou.
#
# Context: a previous installation of this host failed to produce a bootable
# machine. This module makes sure that, when that happens again, the failure
# can be diagnosed afterwards instead of being lost with the wiped root:
#
#   1. journald is persistent: it writes to /var/log/journal, which
#      ./impermanence.nix maps to /persist/var/log, so logs survive reboots
#      and root rollbacks. /etc/machine-id is persisted as well, so the
#      journal of previous boots remains readable. The log of a failed boot
#      can then be inspected from the next (working) boot via `journalctl -b -1`.
#
#   2. every boot attempt is recorded to /persist/boot-introspection/boots.log
#      as early as stage 2, tagged with the systemd boot-id, kernel version and
#      system generation. A "success" record is written only once sshd is
#      actually up. An attempt without a matching success is therefore a
#      boot that failed to reach a usable post-boot state.
#
#   3. the systemd-boot menu is shown for 10s on every boot, so a previous
#      generation can be selected or the kernel command line edited manually
#      when the default entry fails.
#
#   4. stage 1 is explicitly systemd-based (required by the initrd rollback
#      service in ./impermanence.nix). A systemd initrd drops into an
#      emergency shell on the console when stage 1 fails, making initrd
#      failures (disk/disko/filesystem mismatches) debuggable interactively.
#
# How to introspect a failed boot:
#   - next (working) boot:   `boot-introspect`  (helper packaged below), and
#                            `journalctl -b -1` for the full previous log
#   - if stage 2 is never reached: boot any live ISO and inspect the
#     persistent data directly on disk:
#         mount -o subvol=@persist <volume> /mnt
#         cat /mnt/boot-introspection/boots.log
#         journalctl --directory=/mnt/var/log/journal
#   - stage-1 failures: use the emergency shell offered by the initrd on
#     the console.
#   - additionally, the pre-rollback root of every failed boot is preserved
#     for 30 days as a btrfs subvolume under `old_roots` on the root
#     partition (see ./impermanence.nix).
{
  pkgs,
  ...
}:
{
  boot = {
    loader.timeout = 10; # show the boot menu instead of booting the default entry silently
    initrd.systemd.enable = true; # required by boot.initrd.systemd.services.rollback in ./impermanence.nix
  };

  services.journald.extraConfig = ''
    Storage=persistent
    SystemMaxUse=1G
  '';

  # runs as early as possible in stage 2, before anything that could plausibly
  # fail (networking, sshd, display manager...)
  systemd.services.record-boot-attempt = {
    description = "Record a boot attempt to persistent storage (failed-boot introspection)";
    wantedBy = [ "basic.target" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.coreutils ];
    script = ''
      mkdir -p /persist/boot-introspection
      {
        printf '%s attempt boot_id=%s kernel=%s generation=%s\n' \
          "$(date --iso-8601=seconds)" \
          "$(cat /proc/sys/kernel/random/boot_id)" \
          "$(uname -r)" \
          "$(readlink -f /run/current-system 2>/dev/null || echo unknown)"
      } >> /persist/boot-introspection/boots.log
    '';
  };

  # only reached once sshd is actually running, i.e. the machine is remotely
  # usable; `requires`+`after` sshd means this record is NOT written if sshd
  # fails to start
  systemd.services.record-boot-success = {
    description = "Record a successful boot (sshd reached) to persistent storage";
    wantedBy = [ "multi-user.target" ];
    after = [ "sshd.service" ];
    requires = [ "sshd.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.coreutils ];
    script = ''
      mkdir -p /persist/boot-introspection
      {
        printf '%s success boot_id=%s kernel=%s generation=%s\n' \
          "$(date --iso-8601=seconds)" \
          "$(cat /proc/sys/kernel/random/boot_id)" \
          "$(uname -r)" \
          "$(readlink -f /run/current-system 2>/dev/null || echo unknown)"
      } >> /persist/boot-introspection/boots.log
    '';
  };

  environment.systemPackages = [
    (pkgs.writeShellScriptBin "boot-introspect" ''
      set -e
      LOG=/persist/boot-introspection/boots.log
      echo "== recorded boots ($LOG) =="
      cat "$LOG" 2>/dev/null || echo "(no record found)"
      echo
      echo "== journald boots =="
      journalctl --list-boots | tail -15
      echo
      echo "== boot attempts without matching success (failed boots) =="
      found=no
      if [ -f "$LOG" ]; then
        for b in $(awk '$2=="attempt" {att[$3]=1} $2=="success" {ok[$3]=1} END {for (x in att) if (!(x in ok)) print x}' "$LOG"); do
          found=yes
          echo "  $b   (inspect with: journalctl --boot=$b)"
        done
      fi
      [ "$found" = yes ] || echo "  (none)"
      echo
      echo "old pre-rollback roots (kept 30d) are btrfs subvolumes under old_roots on <dedicated volume>"
    '')
  ];
}
