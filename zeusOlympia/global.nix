{ pkgsLib, ... }:
{
  options.wranHearstPublicKey = pkgsLib.mkOption { };
  config = {
    wranHearstPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE+gHdBdYnmkKNQbt9YeSRjomS+eoFEfmusiZ6ooGBEI";
    environment = {
      variables = {
        EDITOR = "nvim";
      };
    };
  };
}
