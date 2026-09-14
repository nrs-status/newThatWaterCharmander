{ pkgsLib, ... }:
{
  options.wranHearstPublicKey = pkgsLib.mkOption { };
  config = {
    wranHearstPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF+Zkx82s6OTrx6Wk4qwC1b9RyiuTFBMW6MZHm32uKyJ root@nixos";
    variables = {
      EDITOR = "nvim";
    };
  };
}
