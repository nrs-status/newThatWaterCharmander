{ localModules, config, ... }:
{
  imports = [ localModules.fs ];
  fs.mainDevicePath = "/dev/nvme0n1";

  environment.persistence."/persist" = {
    users.soc7099 = {
      directories = [
        "persistent"
      ]
      ++ config.miscStaticVals.sharedPersistedUserDirs;
    };
  };
}
