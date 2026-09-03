{
  pkgs,
  pkgsLib,
  frontArmToPlane,
  ...
}:
{
  sops = {
    defaultSopsFile = "${frontArmToPlane.packages.x86_64-linux.secrets}/secrets.yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };

  #ensures /root/.config/sops/age exists
  systemd.tmpfiles.rules = [
    "d /root/.config/sops/age 0700 root root - -"
  ];
  systemd.services.hostSSHToAge = {
    description = "create an age key from the host ssh key in order to be able to decrypt fatp's secrets.yaml as root";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-tmpiles-setup.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgsLib.getExe pkgs.ssh-to-age} -private-key -i /etc/ssh/ssh_host_ed25519_key > /root/.config/sops/age/keys.txt";
    };
  };
}
