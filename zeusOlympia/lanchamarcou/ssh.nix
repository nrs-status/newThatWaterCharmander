{
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
    };
  };

  #the current host's own ssh host key is used as the authorized key for ssh
  #access, for both plat2548 and root
  users.users.plat2548.openssh.authorizedKeys.keys = [
    (builtins.readFile ./sshHostKey.pub)
  ];
  users.users.root.openssh.authorizedKeys.keys = [
    (builtins.readFile ./sshHostKey.pub)
  ];
  networking.firewall.allowedTCPPorts = [ 22 ];
}
