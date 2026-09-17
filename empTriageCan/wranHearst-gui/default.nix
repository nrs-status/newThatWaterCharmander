{ localModules, localLib, ... }:
{
  imports = [
    ../wranHearst-minimal
    (localLib.mkDirectoryImporterModule ./.)
  ]
  ++ (with localModules; [
    #ui
    sway
    audio
  ]);
}
