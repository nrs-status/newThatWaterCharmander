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
        ".local/share/atuin/history.db"
      ];
    };
  };
}
