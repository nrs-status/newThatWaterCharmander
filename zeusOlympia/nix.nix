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
        "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=" # key for binary cache for haskell.nix
      ]; 
    };
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };
}
