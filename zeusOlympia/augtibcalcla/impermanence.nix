{

  environment.persistence."/persist" = {
    users.soc7099 = {
      directories = [
        "persistent"
      ];
      files = [
        ".local/share/atuin/history.db"
      ];
    };
  };
}
