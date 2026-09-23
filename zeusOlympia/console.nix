{ pkgs, ... }:
{
  config.console = {
    font = "ter-128n";
    packages = with pkgs; [ terminus_font ];
  };
}
