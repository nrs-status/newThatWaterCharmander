{ config, ... }:
{

  environment.persistence."/persist" = {
    files = [
      "/etc/ssh/ssh_host_ed25519_key"
    ];
    users.sieyes = {
      directories = [
        "baghdadPlane"
        "daguerreBrick"
        "smithShirtCube"
        "kierLeapMount"

      ] ++ config.sharedPersistedUserDirs ;
      files = [
      ];
    };
  };
}
