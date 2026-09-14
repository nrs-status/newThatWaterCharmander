{ frontArmToPlane, peachRampSkateboard, ... }:
{
  nix = {
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
    settings = {
      allow-import-from-derivation = true;
      sandbox = "relaxed";
      auto-optimise-store = true;
      substituters = [
        "https://cache.iog.io" # binary cache for haskell.nix
        "https://nix-community.cachix.org"
      ];
      trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=" # nix-community
        "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=" # key for binary cache for haskell.nix
      ]; 
    };
    extraOptions = ''
      experimental-features = nix-command flakes
    '';

    registry = {
      frontArmToPlane.flake = frontArmToPlane;
      peachRampSkateboard.flake = peachRampSkateboard;
    };
  };
}
