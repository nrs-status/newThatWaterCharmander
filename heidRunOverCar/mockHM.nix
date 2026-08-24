{ baseLib, hmFlake, hmMockVersion, ... }:
{ pkgs, hmMockModules }:
baseLib.withDebug rec {
  mockUserConfig = {
    home = {
      username = "mockUser";
      homeDirectory = "/home/mockUser";
      stateVersion = hmMockVersion;
    };
  };
  __output = hmFlake.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      mockUserConfig
    ] ++ hmMockModules;
  };
}

