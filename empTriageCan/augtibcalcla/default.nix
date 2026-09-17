{ localModules, localLib, ... }:
{
  imports = [ ../louSelfHit-sofa (localLib.mkDirectoryImporterModule ./.) ] ++ (with localModules; [
    sway
    audio
    telegraf
  ]);
}
