{ localModules, localLib, ... }:
{
  imports = [
    ../wranHearst-gui
    (localLib.mkDirectoryImporterModule ./.)
  ]
  ++ (with localModules; [
    forgejo
    garage
    media
    harmonia
    openBao
    postgresql
    vaultWarden
    xandikos
  ]);
}
