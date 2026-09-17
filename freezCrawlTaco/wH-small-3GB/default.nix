{
  hostModules,
  localLib,
  ...
}:
{
  imports = [
    hostModules.wranHearst-minimal
    (localLib.mkDirectoryImporterModule ./.)
  ];

  virtualisation.vmVariant = {
    virtualisation = {
      diskSize = 30000;
      memorySize = 3000; 
      cores = 4;
      graphics = true; # keeps console=tty0 console=ttyS0 available
    };

  };
}
