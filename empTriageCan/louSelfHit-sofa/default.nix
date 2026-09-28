{ localLib, ... }:
{
  imports = [
    ../heg-tweOnPlant
    (localLib.mkDirectoryImporterModule ./.)
  ];
}
