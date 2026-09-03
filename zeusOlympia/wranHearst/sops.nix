{ frontArmToPlane, ... }:
{
  sops = {
    defaultSopsFile = "${frontArmToPlane.packages.x86_64-linux.secrets}/secrets.yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };

  systemd.services.hostSSHToAge = {
    description = "create an age key from the host ssh key in order to be able to decrypt fatp's secrets.yaml as root";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key > /root/.config/sops/age/keys.txt";
    };
  };
}
