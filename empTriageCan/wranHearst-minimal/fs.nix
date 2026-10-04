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
        "afroHagglesRaccoonHat"
        "pikaExpPianoKey" 
        "lacDrownsMerc"
        ".local/share/bottles" 
        ".local/share/Anki2" 
      ]
      ++ config.miscStaticVals.sharedPersistedUserDirs;

      files = [
      ];

    };
  };
}
