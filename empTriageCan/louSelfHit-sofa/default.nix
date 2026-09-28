{ localLib, ... }:
{
  imports = [
    ../heg-twPlant
    (localLib.mkDirectoryImporterModule ./.)
  ];
}
