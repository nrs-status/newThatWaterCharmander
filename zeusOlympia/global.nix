{ pkgsLib, ... }:
{
  options.wranHearstPublicKey = pkgsLib.mkOption { };
  config = {
    wranHearstPublicKey = builtins.readFile /etc/ssh/ssh_host_ed25519_key.pub;
    environment = {
      variables = {
        EDITOR = "nvim";
      };
    };
  };
}
