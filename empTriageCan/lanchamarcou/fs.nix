{ localModules, config, ... }:
{
  imports = [ localModules.fs ];
  fs.mainDevicePath = "/dev/disk/by-id/ata-HGST_HTS541075A9E680_JD1A001918018M";

  environment.persistence."/persist" = {
    users.plat2548 = {
      directories = [
        "persistent"
      ]
      ++ config.miscStaticVals.sharedPersistedUserDirs;
    };
  };
}
