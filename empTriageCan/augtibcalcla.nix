inputsForModulesExceptPkgs:
{
  system = "x86_64-linux";
  specialArgs = inputsForModulesExceptPkgs;
  modules = [ #these are strings because as paths they are incorrect
    "./global.nix"
    "./globalPackages.nix"
    "./nix.nix"
    "./security"
    "./virtualization.nix"
    "./nixpkgs.nix"
    "./vm.nix"
    "./keyRemappings.nix"
    "./augtibcalcla"
    "./bootIntrospection"
    "./avahi.nix"
    "./telegraf"
    "./sway"
    "./impermanence"
    "./openssh.nix"

  ];
}
