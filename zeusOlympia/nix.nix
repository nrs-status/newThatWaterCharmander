{ frontArmToPlane, peachRampSkateboard, config, ... }:
let
  # MagicDNS FQDN of wranHearst in the headscale tailnet (see ./headscale);
  # guarded so imports without the tailnet module still evaluate
  magicFqdn = if config ? tailnet then config.tailnet.magicFqdn else "wranHearst.home";
in
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
        # NOTE: this uses the MagicDNS name of wranHearst in the headscale
        # tailnet (wranHearst.tailnet.internal, see ./headscale). it is a
        # plain DNS name (served by the tailscale resolver wired into the
        # system resolver), so nix CAN resolve it: unlike the old mDNS name
        # wranHearst.local, MagicDNS works through the `files dns` NSS lookup
        # nix hardcodes (the query goes to resolv.conf -> systemd-resolved ->
        # tailscale), so the substituter is not silently skipped. before a
        # host is enrolled into the tailnet the name does not resolve and nix
        # skips the substituter until enrollment, which is harmless.
        "http://${magicFqdn}:5000"
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
