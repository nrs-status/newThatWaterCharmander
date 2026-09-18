# Caches a dev shell so that opening a new terminal does not evaluate the flake
# every time ("alternative A" of the shell-caching exploration, see
# ../SUMMARY.md).
#
# Why: `nix develop <flakeref>#<shell>` re-resolves and evaluates the flake on
# every invocation (~14.5 s on an evaluation-cache miss, ~1.8 s on a hit) even
# when everything is already built, because evaluation happens before Nix can
# know whether anything needs building. Merely pre-building the shell's
# dependency closure (the previous `inputDerivation`-based module) therefore
# never removed the per-terminal latency.
#
# How this module works instead:
#
#   1. A user systemd service runs once per login and records the *evaluated*
#      environment with `nix print-dev-env --profile`. This evaluates the
#      shell, builds/substitutes its whole dependency closure (which the old
#      module did explicitly via `inputDerivation`), writes the resulting
#      `*-env` store path into a profile and registers it as a GC root.
#      `print-dev-env` is used instead of `nix develop` because it does not
#      run the shell's (interactive) `shellHook` and therefore exits 0 even
#      when the hook `exec`s an interactive shell (nushell here).
#
#   2. Terminals start `shellCacher.launcher` (see below) instead of
#      `nix develop <flakeref>#<shell>`. The launcher enters the recorded
#      environment with `nix develop <profile>`, which Nix implements by
#      reading the recorded `*-env` directly -- no flake is evaluated, no
#      derivation is built (~0.25 s per terminal, compared with ~1.8 s warm /
#      ~14.5 s cold for the flake reference).
#
#   3. If the recorded profile does not exist yet (first terminal of a session
#      racing the login service, or the service failing), the launcher
#      serializes on the service via `systemctl --user start --wait`
#      (a no-op once `RemainAfterExit` has made it active). If the profile is
#      still absent afterwards the launcher prints why and drops the user into
#      a plain bash shell, instead of silently re-evaluating the flake (which
#      used to cost ~15 s with no explanation). `shellCacher.flakeRef`, when
#      set, is reported as the manual escape hatch back into the dev shell.
#
# The profile is refreshed when the shell changes because the record script's
# store path embeds `shell.drvPath`: a changed shell yields a changed
# `ExecStart`, i.e. a changed unit, which `nixos-rebuild switch` (and the next
# login) restart.
{ config, lib, pkgsLib, pkgs, ... }:
let
  cfg = config.shellCacher;
  name = cfg.shell.name;

  serviceName = "shellCacher-${name}";

  # The recorded environment lives under the user's home. `%h` is expanded by
  # the *user* systemd manager in the ExecStart argument below; the launcher
  # computes the same path from `$HOME` at runtime.
  profilePath = ".cache/nix/shellCacher/${name}";

  # Same reasoning as the old module: the user manager's PATH contains only a
  # few core packages and does not survive a rebuild when a specific
  # `/nix/store/...-nix-X.Y/bin/nix` is hardcoded, so resolve `nix` through
  # the stable profile symlink `/run/current-system/sw/bin` (the same one a
  # login shell uses).
  #
  # The shell's `drvPath` is interpolated directly (not passed through a
  # flakeref), so the service never needs the flake registry, and the drv is
  # pinned into the system closure through the script's store references.
  # A drv path must not be given to `--expr`: evaluation is pure, so absolute
  # store paths are only accessible as plain installables.
  #
  # After a successful record, superseded profile generations are unlinked so
  # their closures (the shell's dependency closure is ~20 GiB / 2515 store
  # paths for the `sieyes` shell) can be garbage-collected instead of piling
  # up as GC roots.
  recordScript = pkgs.writeShellScript "record${name}Env" ''
    set -euo pipefail
    export PATH="/run/current-system/sw/bin:$PATH"
    mkdir -p "$(dirname "$1")"
    nix print-dev-env --profile "$1" ${cfg.shell.drvPath} >/dev/null

    # keep only the generation the profile currently points at
    if [ -e "$1" ]; then
      current="$(dirname "$1")/$(basename "$(readlink "$1")")"
      for gen in "$1"-[0-9]*-link; do
        [ "$gen" = "$current" ] || rm -f -- "$gen"
      done
    fi
  '';

  launcher = pkgs.writeShellApplication {
    name = "enter-${name}";
    meta.mainProgram = "enter-${name}"; # lets `lib.getExe` work without warnings
    text =
      let
        nixBin = "/run/current-system/sw/bin/nix";
        systemctlBin = "/run/current-system/sw/bin/systemctl";
        bashBin = "${pkgs.bashInteractive}/bin/bash";
      in
      ''
        profile="$HOME/${profilePath}"

        # fast path: the login service already recorded the environment
        if [[ -e "$profile" ]]; then
          exec "${nixBin}" develop "$profile"
        fi

        # first terminal of a session (or the service failed earlier): make
        # sure the recording has happened before deciding what to do
        status=0
        "${systemctlBin}" --user start --wait "${serviceName}.service" || status=$?

        if [[ -e "$profile" ]]; then
          exec "${nixBin}" develop "$profile"
        fi

        # Fallback: the recorded environment could not be produced. Do not
        # silently re-evaluate the flake (that used to cost ~15 s and hid the
        # failure); explain why and leave the user in a plain bash shell.
        {
          echo
          echo "enter-${name}: falling back to a plain bash shell."
          echo "The recorded dev-shell environment was not available:"
          echo "  profile: $profile (missing or unusable)"
          echo "  service: ${serviceName}.service (systemctl exit status: $status)"
          echo
          echo "This usually means the shellCacher service has not finished yet,"
          echo "failed, or was never started. Retry the recording with:"
          echo "  systemctl --user start ${serviceName}.service"
        ${lib.optionalString (cfg.flakeRef != null) ''
          echo
          echo "To enter the dev shell without the cache (slow):"
          echo "  nix develop ${cfg.flakeRef}"
        ''}
          echo
        } >&2
        exec "${bashBin}"
      '';
  };
in
{
  options.shellCacher = {
    # untyped in the previous version; a dev shell is always a derivation
    shell = pkgsLib.mkOption {
      type = pkgsLib.types.package;
      description = "the dev shell (pkgs.mkShell ...) whose environment should be cached";
    };

    flakeRef = pkgsLib.mkOption {
      type = pkgsLib.types.nullOr pkgsLib.types.str;
      default = null;
      description = ''
        dev shell as a flake reference (e.g. "frontArmToPlane#sieyes"), reported
        by `shellCacher.launcher`'s fallback message as the manual way back into
        the shell when the recorded profile is unavailable. Must refer to a
        shell in the system's flake registry (see zeusOlympia/nix.nix); must not
        be an interpolated flake input, whose /nix/store copy contains a `.git`
        entry that trips nix's libgit2 ownership check.
      '';
    };

    launcher = pkgsLib.mkOption {
      type = pkgsLib.types.package;
      readOnly = true;
      description = ''
        terminal command that enters the cached shell without evaluating the
        flake; meant to be used by sway keybindings (`zeusOlympia/sway/swayDecl.nix`)
        and sway startup scripts (`zeusOlympia/sway/setupWorkspaces.nix`)
      '';
    };
  };

  config = {
    shellCacher.launcher = launcher;

    # `default.target` is the main target of the *user* systemd manager; the
    # previous version used `multi-user.target`, which only exists in the
    # system manager (`systemctl --user show multi-user.target` reports
    # LoadState=not-found), so the unit was only ever started by
    # `nixos-rebuild switch` and never on login.
    systemd.user.services."${serviceName}" = {
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "oneshot";

        # keep the unit active after finishing so that the launcher's
        # `systemctl --user start --wait` is a no-op instead of re-running
        # the record for every terminal
        RemainAfterExit = true;

        # `%h` expands to the user's home in the user systemd manager
        ExecStart = "${recordScript} %h/${profilePath}";

        #don't compete with rest of login sequence
        Nice = 19;
        IOSchedulingClass = "idle";
      };
    };

    environment.systemPackages = [ launcher ];
  };
}
