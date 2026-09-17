{ localModules, localLib, ... }:
{
  imports = [ ../louSelfHit-sofa (localLib.mkDirectoryImporterModule ./.) ] ++ (with localModules; [
    telegraf
  ]);
}
