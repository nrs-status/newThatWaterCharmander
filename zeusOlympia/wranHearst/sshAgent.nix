# An ssh-agent holding the SSH private keys that sops-nix decrypts
# (see ./sops.nix), so that `sieyes` can authenticate SSH connections
# (e.g. to soc7099 and plat2548) without ever touching the key files:
# the agent loads them once at boot from the root-owned decrypted
# secrets, then exposes a unix socket that only `sieyes` may talk to.
# `sieyes` sessions get SSH_AUTH_SOCK via environment.sessionVariables
# below, which ssh(1) uses to find the agent automatically.
#
# IMPORTANT: the agent itself must run AS `${user}`, not as root.
# ssh-agent(1) checks the euid of every client connecting to its
# socket against its own uid and refuses mismatches
# ("uid mismatch: peer euid 1000 != uid 0"); a root-owned agent would
# therefore reject every connection from `${user}` even if the socket
# were chowned to ${user}.  Running the agent as ${user} makes ${user}
# connections pass that check.  The agent never reads the key files
# itself: the (privileged, `+`-prefixed) ExecStartPost runs ssh-add as
# root, which reads the root-owned decrypted secrets and pushes the key
# material into the agent over the socket (root clients are always
# accepted, which is what allows a root process to load keys into a
# ${user}-owned agent).  The keys therefore remain exclusively
# root-owned while being usable by ${user} only through the agent.
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
      #the agent runs as ${user} so ${user}'s ssh(1) passes ssh-agent's
      #peer-euid check (see the comment at the top of this file)
      User = user;
      #ssh-agent(1) daemonizes (unless given -D) after binding the socket,
      #so forking lets systemd run ExecStartPost only once the socket exists
      Type = "forking";
      RuntimeDirectory = "sopsSSHAgent";
      RuntimeDirectoryMode = "0755";
      UMask = "0077";
      Environment = "SSH_AUTH_SOCK=${agentSocket}";
      ExecStart = "${pkgs.openssh}/bin/ssh-agent -a ${agentSocket}";
      #the leading "+" runs this script with full root privileges even
      #though the service itself runs as ${user}: only root may read the
      #decrypted (root-owned, mode 0600) key files, and ssh-add(1) as the
      #client is what reads the key file and hands it to the agent; root
      #clients are accepted by ssh-agent even though the agent runs as
      #${user}, so the keys are loaded without ${user} ever being able to
      #read them (see the comment at the top of this file).  A missing or
      #unloadable key fails the service loudly (the list itself is also
      #asserted non-empty at build time, see the assertion above).
      ExecStartPost = "+" + (pkgs.writeShellScript "sopsSSHAgent-addKeys" ''
        set -eu
        for key in ${pkgsLib.escapeShellArgs keyPaths}; do
          ${pkgs.openssh}/bin/ssh-add "$key"
        done
      '');
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  #expose the agent socket to every session of ${user} (login shells via
  #/etc/set-environment, systemd user sessions via its environment
  #generator); ssh(1) then uses the agent without further configuration
  environment.sessionVariables.SSH_AUTH_SOCK = agentSocket;
}
