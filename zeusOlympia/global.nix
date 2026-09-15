{ pkgsLib, ... }:
{
  options = {
    wranHearstPublicKey = pkgsLib.mkOption { };
    sharedPersistedUserDirs = pkgsLib.mkOption { };
  };
  config = {
    wranHearstPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE+gHdBdYnmkKNQbt9YeSRjomS+eoFEfmusiZ6ooGBEI";
    sharedPersistedUserDirs = [

      #persisting entire state directories to handle everything the same way. can sometimes do file-by-file but e.g. `zoxide` tries to create a new file and then move it to `.local/share/zoxide/db.zo`, which is not allowed if we declare it as an `impermanence` file, because it is then mounted (so renaming that file or `mv`ing another file over it is disallowed)
      ".local/share/zoxide"
      ".local/share/atuin"
    ];
    environment = {
      variables = {
        EDITOR = "nvim";
      };
    };
  };
}
