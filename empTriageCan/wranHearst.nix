inputsForModulesExceptPkgs:
{
  system = "x86_64-linux";
  specialArgs = inputsForModulesExceptPkgs;
  modules = [ #these are strings because as paths they are incorrect
    "./core.nix"
    "./audio.nix"
    "./bluetooth.nix"
    "./globalPackages.nix"
    "./keyRemappings.nix"
    "./nix.nix"
    "./security.nix"
    "./sway"
    "./virtualization.nix"
    "./sieyes.nix"
    "./wranHearst"
    "./nixpkgs.nix"
    "./sops.nix"
  ];
}

