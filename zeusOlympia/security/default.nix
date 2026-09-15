{
  sopsFlake,
  pkgsLib,
  pkgs,
  utils,
  config,
  ...
}:
let
  # paths of the files impermanence persists (see environment.persistence below)
  persistDir = "/persist/etc/kierLeapMount";

  #These are the names of the services spawned by impermanence to persist these files.
  #they are used in the "before" attribute in the service declarations below
  sopsConfigPersistUnit = "persist-${utils.escapeSystemdPath "${persistDir}/.sops.yaml"}.service";
  secretsPersistUnit = "persist-${utils.escapeSystemdPath "${persistDir}/secrets.yaml"}.service";
  #the ed25519 host ssh key is persisted by impermanence (see ../impermanence),
  #which exposes /persist/etc/ssh/ssh_host_ed25519_key at /etc/ssh/... (bind
  #mount, or symlink until the key first exists) before local-fs.target, so
  #sops and the services below read it from its normal, non-persistent
  #location. this is the unit that creates that mount/symlink
  hostSshKey = "/etc/ssh/ssh_host_ed25519_key";
  hostSshKeyPersistUnit = "persist-${utils.escapeSystemdPath "/persist/etc/ssh/ssh_host_ed25519_key"}.service";
in
{
  imports = [ sopsFlake.nixosModules.sops ];

  security = {
    rtkit.enable = true;
    #passwordless access to rfkill so bluetooth can be toggled
    sudo.extraRules = [
      {
        groups = [ "wheel" ];
        commands = [
          {
            command = "/run/current-system/sw/bin/rfkill";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
  };

  #the rest of this section sets up a host-specific secrets file

  environment.persistence."/persist".files = [ "/etc/kierLeapMount/secrets.yaml" "/etc/kierLeapMount/.sops.yaml" ];

  sops = {
    defaultSopsFile = "/etc/kierLeapMount/secrets.yaml";
    age.sshKeyPaths = [ hostSshKey ];
    #secrets.yaml only comes into existence at boot (see the services below),
    #so it cannot be validated at build time
    validateSopsFiles = false;
    #the secrets must be decrypted after local-fs.target, i.e. after
    #impermanence has bind mounted /etc/kierLeapMount/secrets.yaml and the
    #services below have run. without this, decryption would happen in the
    #activation script, which runs before systemd (and therefore before the
    #mount and the services exist)
    useSystemdActivation = true;
  };

  systemd.services.hostSSHToAge = {
    description = "create an age key from the host ssh key";
    #must run before local-fs.target: kierLeapMountSopsConfig consumes this
    #unit's output and has to run before impermanence creates the bind mounts
    #for the sops files, which happens before local-fs.target too
    wantedBy = [ "local-fs.target" ];
    before = [ "local-fs.target" ];
    #/persist is mounted by stage 1 (neededForBoot), but the key is only
    #reachable at its non-persistent location (see ../openssh.nix) once
    #impermanence has created the mount/symlink for it, so this unit must run
    #after impermanence's persist unit for the key
    after = [ hostSshKeyPersistUnit ];
    unitConfig.DefaultDependencies = false;
    serviceConfig = {
      Type = "oneshot";
      UMask = "0077";
      #the age dir is created here instead of relying on a tmpfiles rule:
      # systemd-tmpfiles-setup.service runs after local-fs.target, so
      #depending on it would deadlock with the ordering above,
      #and the tmpfiles rule only takes effect long after this unit has run
      ExecStart = pkgs.writeShellScript "hostSSHToAge" ''
        mkdir -p /root/.config/sops/age
        chmod 0700 /root/.config/sops/age
        #generate the host key if it is missing (virgin /persist on first
        #boot): this runs before local-fs.target, i.e. before sshd-keygen,
        #and everything below (sshd, sops decryption) depends on the key.
        #the key is written straight into /persist (where impermanence
        #persists it) and renamed into place there: renaming onto the
        #symlink/bind mount at ${hostSshKey} itself would replace it with a
        #plain file that does not survive the root wipe
        persistKey=/persist/etc/ssh/ssh_host_ed25519_key
        if [ ! -s ${hostSshKey} ]; then
          mkdir -p /persist/etc/ssh
          ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -N "" -f "''${persistKey}.new"
          mv -f "''${persistKey}.new" "$persistKey"
          mv -f "''${persistKey}.new.pub" "$persistKey.pub"
        fi
        ${pkgsLib.getExe pkgs.ssh-to-age} -private-key -i ${hostSshKey} \
          > /root/.config/sops/age/keys.txt
      '';
    };
  };

  systemd.services.kierLeapMountSopsConfig = {
    description = "write the host-specific sops creation rules to /persist";
    #must run before impermanence's persist unit for .sops.yaml, which runs
    #before local-fs.target, so this unit has to drop its default
    #dependencies as well to avoid an ordering cycle (see hostSSHToAge)
    wantedBy = [ "local-fs.target" ];
    before = [
      "local-fs.target"
      sopsConfigPersistUnit
    ];
    after = [ "hostSSHToAge.service" ];
    unitConfig.DefaultDependencies = false;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "kierLeapMountSopsConfig" ''
        set -eu
        mkdir -p ${persistDir}
        host=${config.networking.hostName}
        #the public age key corresponding to the private key hostSSHToAge
        #creates at /root/.config/sops/age/keys.txt; fall back to deriving it
        #from the ssh host key directly if that file is missing
        if [ -s /root/.config/sops/age/keys.txt ]; then
          pub=$(${pkgs.age}/bin/age-keygen -y /root/.config/sops/age/keys.txt)
        else
          pub=$(${pkgsLib.getExe pkgs.ssh-to-age} -private-key -i ${hostSshKey} \
            | ${pkgs.age}/bin/age-keygen -y)
        fi
        #rewrite in place so that the file keeps its inode if it is already
        #bind mounted
        cat > ${persistDir}/.sops.yaml <<EOF
        keys:
          - &''${host} ''${pub}
        creation_rules:
          - path_regex: secrets\.yaml
            key_groups:
              - age:
                - *''${host}
        EOF
      '';
    };
  };

  systemd.services.kierLeapMountSecretsFile = {
    description = "touch /persist's secrets.yaml if it does not exist yet";
    #must run before impermanence's persist unit for secrets.yaml, which runs
    #before local-fs.target, so this unit has to drop its default
    #dependencies as well to avoid an ordering cycle (see hostSSHToAge)
    wantedBy = [ "local-fs.target" ];
    before = [
      "local-fs.target"
      secretsPersistUnit
    ];
    unitConfig.DefaultDependencies = false;
    serviceConfig = {
      Type = "oneshot";
      UMask = "0077";
      ExecStart = pkgs.writeShellScript "kierLeapMountSecretsFile" ''
        mkdir -p ${persistDir}
        if [ ! -e ${persistDir}/secrets.yaml ]; then
          touch ${persistDir}/secrets.yaml
        fi
      '';
    };
  };
}
