{ localModules, localLib, swayPkgs, ... }:
{
  imports = [
    ../wranHearst-minimal
    (localLib.mkDirectoryImporterModule ./.)
  ]
  ++ (with localModules; [
    #ui
    audio
  ]);

  config.environment.systemPackages = [ swayPkgs.full ];
}
