inputsForModulesExceptPkgs:
{
  system = "x86_64-linux";
  specialArgs = inputsForModulesExceptPkgs;
  modules = [ #these are strings because as paths they are incorrect
    "./global.nix"
    "./audio.nix"
    "./bluetooth.nix"
    "./globalPackages.nix"
    "./keyRemappings.nix"
    "./nix.nix"
    "./security"
    "./sway"
    "./virtualization.nix"
    "./sieyes.nix"
    "./wranHearst"
    "./kubernetes"
    "./nixpkgs.nix"
    "./vm.nix"
    "./postgresql"
    "./forgejo"
    "./garage"
    "./harmonia"
    "./vaultWarden"
    "./openBao"
    "./impermanence"
    "./avahi.nix"
    "./bootIntrospection"
    "./openssh.nix"
  ];
}

