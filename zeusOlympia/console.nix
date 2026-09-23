{ pkgs, ... }:
{
  config.console = {
    font = "ter-124n";
    packages = with pkgs; [ terminus_font ];
  };
}
