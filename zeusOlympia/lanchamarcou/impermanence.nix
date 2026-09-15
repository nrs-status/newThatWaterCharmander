{ config, ... }:
{

  environment.persistence."/persist" = {
    users.plat2548 = {
      directories = [
        "persistent"
      ] ++ config.sharedPersistedUserDirs;
    };
  };
}
