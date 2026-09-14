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
        ".local/share/zoxide/db.zo"
        
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
