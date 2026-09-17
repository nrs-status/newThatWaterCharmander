{ localModules, localLib, ... }:
{
  imports =
    [ ../louSelfHit-sofa (localLib.mkDirectoryImporterModule ./.) ] ++ (with localModules; [
      #ui
      sway
      audio
      libvirtd

      #services
      forgejo
      garage
      harmonia
      openBao
      postgresql
      vaultWarden
    ]);
}
