{ pkgs, ... }:
shell:
{
  systemd.user.services."cache${shell.name}Shell" = {
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.lib.getExe pkgs.nix} build --expr ${shell.inputDerivation} --no-link --print-out-paths";

      #don't compete with rest of login sequence
      Nice = 19;
      IOSchedulingClass = "idle";
    };
  };
}


