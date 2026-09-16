# An ssh-agent holding the SSH private keys that sops-nix decrypts
# (see ./sops.nix), so that `sieyes` can authenticate SSH connections
# (e.g. to soc7099 and plat2548) without ever touching the key files:
# the agent loads them once at boot from the root-owned decrypted
# secrets, then exposes a unix socket that only `sieyes` may talk to.
# `sieyes` sessions get SSH_AUTH_SOCK via environment.sessionVariables
# below, which ssh(1) uses to find the agent automatically.
{
  config,
  pkgs,
  pkgsLib,
  ...
}:
let
  user = "sieyes";

  #the SSH private keys declared in ./sops.nix; sops-nix decrypts them to
  #/run/secrets/<name> (owned by root, mode 0600, see the declaration there)
  sshSecrets = pkgsLib.filterAttrs (
    name: _: pkgsLib.hasPrefix "ssh/" name
  ) config.sops.secrets;
  keyPaths = map (secret: secret.path) (pkgsLib.attrValues sshSecrets);

  agentRuntimeDir = "/run/sopsSSHAgent";
  agentSocket = "${agentRuntimeDir}/agent.sock";
  sopsUnit = "sops-install-secrets.service";
in
{
  assertions = [
    {
      assertion = keyPaths != [ ];
      message = "wranHearst sshAgent: no sops secrets named ssh/* exist in config.sops.secrets (see ./sops.nix)";
    }
  ];

  systemd.services.sopsSSHAgent = {
    description = "ssh-agent holding the sops-nix SSH keys for ${user}";
    documentation = [ "man:ssh-agent(1)" "man:ssh-add(1)" ];
    wantedBy = [ "multi-user.target" ];
    #the decrypted key files must exist before the agent tries to load them
    after = [ sopsUnit ];
    wants = [ sopsUnit ];
    serviceConfig = {
      #ssh-agent(1) daemonizes (unless given -D) after binding the socket,
      #so forking lets systemd run ExecStartPost only once the socket exists
      Type = "forking";
      RuntimeDirectory = "sopsSSHAgent";
      RuntimeDirectoryMode = "0755";
      UMask = "0077";
      Environment = "SSH_AUTH_SOCK=${agentSocket}";
      ExecStart = "${pkgs.openssh}/bin/ssh-agent -a ${agentSocket}";
      ExecStartPost = pkgs.writeShellScript "sopsSSHAgent-addKeys" ''
        set -eu
        #ssh-add every decrypted ssh/* secret; a missing or unloadable key
        #fails the service loudly (the list itself is also asserted non-empty
        #at build time, see the assertion above)
        for key in ${pkgsLib.escapeShellArgs keyPaths}; do
          ${pkgs.openssh}/bin/ssh-add "$key"
        done
        #the agent (and therefore the socket) runs as root, because the
        #decrypted secrets are root-owned; hand the socket to ${user} so
        #only ${user} can talk to the agent (0600 mode comes from UMask)
        ${pkgs.coreutils}/bin/chown ${user} ${agentSocket}
      '';
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  #expose the agent socket to every session of ${user} (login shells via
  #/etc/set-environment, systemd user sessions via its environment
  #generator); ssh(1) then uses the agent without further configuration
  environment.sessionVariables.SSH_AUTH_SOCK = agentSocket;
}
