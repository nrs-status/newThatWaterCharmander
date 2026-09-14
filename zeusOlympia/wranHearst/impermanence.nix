{

  environment.persistence."/persist" = {
    users.sieyes = {
      directories = [
        "baghdadPlane"
        "daguerreBrick"
        "smithShirtCube"
        "kierLeapMount"
      ];
      files = [
        
        {
          file = ".local/share/atuin/history.db";
          parentDirectory = {
            user = "sieyes";
          };
        }
      ];
    };
  };
}
