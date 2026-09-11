{ pkgsLib, ... }:
{
  options.wranHearstPublicKey = pkgsLib.mkOption { };
  config = {
    wranHearstPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHODPKUTWxBP0NqrBbjmHp4P1yzfTygNHatqCnA4dnJK";
    environment = {
      variables = {
        EDITOR = "nvim";
      };
    };
  };
}
