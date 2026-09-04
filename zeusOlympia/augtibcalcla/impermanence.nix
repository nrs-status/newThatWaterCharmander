{ pkgs, pkgsLib, impermanenceFlake, ... }:
{
  imports = [ impermanenceFlake.nixosModules.impermanence ];

  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/var/log"
      "/var/lib/NetworkManager"
      "/var/lib/systemd"
      "/var/lib/nixos"
    ];
    files = [ "/etc/machine-id" ];
    users.plat2548 = {
      directories = [ "testdir" ];
    };
  };
  fileSystems."/persist".neededForBoot = true;

  #wipe root on reboot
  #the host boots with systemd stage 1, so this cannot be done with
  #`boot.initrd.postResumeCommands`; it has to be an initrd systemd service
  #running before sysroot.mount instead
  boot.initrd.systemd.services.rollback = {
    description = "Rollback BTRFS root subvolume to a pristine state";
    wantedBy = [ "initrd.target" ];
    after = [
      "systemd-udevd.service"
      "dev-disk-by\\x2dpartlabel-disk\\x2dmain\\x2droot.device"
    ];
    before = [ "sysroot.mount" ];
    unitConfig.DefaultDependencies = "no";
    serviceConfig.Type = "oneshot";
    path = with pkgs; [
      btrfs-progs
      coreutils
      findutils
    ];
    script = ''
      if [ ! -b /dev/disk/by-partlabel/disk-main-root ]; then
          echo "rollback: root btrfs device not present, skipping wipe"
          exit 0
      fi

      mkdir /btrfs_tmp
      mount /dev/disk/by-partlabel/disk-main-root /btrfs_tmp
      if [[ -e /btrfs_tmp/root ]]; then
          mkdir -p /btrfs_tmp/old_roots
          timestamp=$(date --date="@$(stat -c %Y /btrfs_tmp/root)" "+%Y-%m-%-d_%H:%M:%S")
          mv /btrfs_tmp/root "/btrfs_tmp/old_roots/$timestamp"
      fi

      delete_subvolume_recursively() {
          IFS=$'\n'
          for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
              delete_subvolume_recursively "/btrfs_tmp/$i"
          done
          btrfs subvolume delete "$1"
      }

      for i in $(find /btrfs_tmp/old_roots/ -maxdepth 1 -mtime +30); do
          delete_subvolume_recursively "$i"
      done

      btrfs subvolume create /btrfs_tmp/root
      umount /btrfs_tmp
    '';
  };
}
