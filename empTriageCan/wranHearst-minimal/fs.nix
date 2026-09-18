{ localModules, config, ... }:
{
  imports = [ localModules.fs ];
  fs.mainDevicePath = "/dev/nvme0n1";

  environment.persistence."/persist" = {
    users.sieyes = {
      directories = [
        "baghdadPlane"
        "daguerreBrick"
        "smithShirtCube"
        "afg-ichigoGest"
        "mobSitChi"
      ]
      ++ config.miscStaticVals.sharedPersistedUserDirs;

      files = [
      ];

    };
  };
}
