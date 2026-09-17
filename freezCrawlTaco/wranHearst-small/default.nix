{
  hostModules,
  localLib,
  pkgs,
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
      memorySize = 2000; # sway + the host's services + a browser
      cores = 4;
      graphics = true; # keeps console=tty0 console=ttyS0 available
    };

  };
}
