{ pkgs, ... }:
{
  config.console = {
    font = "ter-132n";
    packages = with pkgs; [ terminus_font ];
  };
}
