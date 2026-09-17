{ localLib, ... }:
{
  imports = [
    ../louSelfHit-sofa
    (localLib.mkDirectoryImporterModule ./.)
  ];
}
