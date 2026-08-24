{ pkgs, ... }:
{ environment.systemPackages = with pkgs; [ bluez blueman ]; }
