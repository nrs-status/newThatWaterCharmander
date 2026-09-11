{ config, ... }:
{
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
    };
    # store host keys in /persist: the root subvolume is wiped on every boot
    # (see ./impermanence.nix), so keys under /etc/ssh are regenerated each
    # boot and every client gets a host-key-changed warning. pointing
    # services.openssh.hostKeys at /persist makes the sshd-keygen unit
    # generate the keys there if missing (no impermanence bind needed)
    hostKeys = [
      {
        path = "/persist/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
      {
        path = "/persist/etc/ssh/ssh_host_rsa_key";
        type = "rsa";
        bits = 4096;
      }
    ];
  };

  users.users = {
    plat2548.openssh.authorizedKeys.keys = [
      config.wranHearstPublicKey
    ];
    root.openssh.authorizedKeys.keys = [ config.wranHearstPublicKey ];
  };

  networking.firewall.allowedTCPPorts = [ 22 ];
}
