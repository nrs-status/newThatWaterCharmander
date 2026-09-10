{ ... }:
{ shell, pkgs }:
{
  systemd.user.services."cache${shell.name}Shell" = {
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";

      # systemd user services can neither resolve an unqualified `nix` (the user
      # manager's PATH only contains the store paths of a few core packages) nor
      # survive a rebuild when a specific `/nix/store/...-nix-X.Y/bin/nix` is
      # hardcoded (the store path changes on every nix version bump and may be
      # garbage-collected afterwards). `nix` from the stable profile symlink
      # `/run/current-system/sw/bin` (the same one a login shell uses) always
      # resolves, including right after a `nixos-rebuild`, so the service stays
      # restartable as a plain user.
      #
      # The shell's `inputDerivation` store path is passed directly as the
      # installable. It must not be given to `--expr`: nix evaluation is pure by
      # default, and accessing an absolute path inside an `--expr` argument is
      # therefore forbidden. Realizing the store path (plus `--no-link`) caches
      # the whole input closure of the shell, so after a rebuild only the newly
      # changed dependencies get built.
      ExecStart = pkgs.writeShellScript "cache${shell.name}Shell" ''
        export PATH="/run/current-system/sw/bin:$PATH"
        exec nix build ${shell.inputDerivation} --no-link --print-out-paths
      '';

      #don't compete with rest of login sequence
      Nice = 19;
      IOSchedulingClass = "idle";
    };
  };
}
