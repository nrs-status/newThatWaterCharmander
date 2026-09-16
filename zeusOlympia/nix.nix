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
        "https://colmena.cachix.org"
        #my cache (harmonia on wranHearst, see ./harmonia)
        #
        # NOTE: this must stay a name resolvable via unicast DNS (the LAN
        # router serves `wranHearst.home` from its DHCP leases and tracks
        # address changes), NOT the mDNS name `wranHearst.local`. Nix
        # hardcodes `__nss_configure_lookup("hosts", "files dns")`
        # (preloadNSS() in src/libstore/globals.cc) so sandboxed builds never
        # touch nscd/nsncd, which means nix cannot resolve mDNS-only `.local`
        # names and would silently skip this substituter on every build.
        "http://wranHearst.home:5000"
      ];
      trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=" # nix-community
        "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=" # key for binary cache for haskell.nix
        "colmena.cachix.org-1:7BzpDnjjH8ki2CT3f6GdOk7QAzPOl+1t3LvTLXqYcSg="
        (builtins.readFile ./harmonia/cache-key.pub) #my cache
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
