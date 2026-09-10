# Summary

Task: add a sway key binding for `$mod+n` that prints all notifications to a file in
`/tmp` and clears them from the interface.

1. **Read `./instructions.txt`** — NixOS system; add `$mod+n` binding in sway to dump
   notifications to `/tmp` and clear them; write this summary; end with a
   `notify-send` containing the git branch.

2. **Explored the flake** to find where sway is configured:
   - `flake.nix` → `heidRunOverCar/` (lib: `mkNixOS`, `mkSwayConfig`, `mkWaybarConfig`, HM mocks) →
     `zeusOlympia/` (host modules) → `zeusOlympia/sway/`.
   - `zeusOlympia/sway/default.nix` installs `mako` (notification daemon) and builds the
     sway config via `localLib.mkSwayConfig { swayNixConfig = import ./swayDecl.nix ... }`.
   - `zeusOlympia/sway/swayDecl.nix` holds `wayland.windowManager.sway.config.keybindings`
     (mako is started in sway's `startup`), so this is the file to edit.

3. **Probed mako's control interface** (`makoctl --help`) on the live session:
   - `makoctl list -j` serializes *all currently displayed* notifications as JSON.
   - `makoctl dismiss --all` clears them from the interface (they go to mako's history,
     still recoverable via `makoctl restore`).
   - Chaining with `&&` makes the dismiss a fail-safe: nothing is cleared unless the
     dump succeeded.

4. **Added the binding** in `zeusOlympia/sway/swayDecl.nix` (inside `config.keybindings`,
   `pkgsLib.mkOptionDefault` set), next to the other `exec` bindings:

   ```nix
   "${modifier}+n" =
     ''exec --no-startup-id ${pkgs.mako}/bin/makoctl list -j | ${pkgs.jq}/bin/jq -r ".[] | \"[\(.urgency)] \(.app_name): \(.summary)\n\(.body)\n\"" > /tmp/mako-notifs_$(date +%F-%T).txt && ${pkgs.mako}/bin/makoctl dismiss --all'';
   ```

   Design notes:
   - `mako` and `jq` are referenced by store path (interpolated), so neither needs to be
     on the user's `PATH` (jq is not in `environment.systemPackages`).
   - sway's `exec` runs the whole command through `sh -c`, so the pipe, the `> /tmp/...`
     redirect and `$(date +%F-%T)` are evaluated at binding-press time (same pattern as
     the existing `$mod+p` / `Print` grim bindings).
   - jq renders the JSON as readable text: `[urgency] app: summary`, then the body.
   - Timestamped filename so successive presses never overwrite a previous dump.

5. **Verified the rendered sway config**: evaluated `heidRunOverCar/mkSwayConfig.nix`
   (the home-manager-mock pipeline used by `zeusOlympia/sway/default.nix`) with the
   flake's pinned inputs; the generated `sway.conf` contains the expected line:

   ```
   bindsym Mod4+n exec --no-startup-id /nix/store/...-mako-1.11.0/bin/makoctl list -j | /nix/store/...-jq-1.8.2-bin/bin/jq -r ".[] | \"[\(.urgency)] \(.app_name): \(.summary)\n\(.body)\n\"" > /tmp/mako-notifs_$(date +%F-%T).txt && /nix/store/...-mako-1.11.0/bin/makoctl dismiss --all
   ```

6. **Tested the exact rendered command end-to-end** against the live mako instance:
   sent two `notify-send` test notifications, ran the command, and confirmed:
   - `/tmp/mako-notifs_<timestamp>.txt` was created containing both notifications
     (urgency, app name, summary, body);
   - `makoctl list` showed an empty interface afterwards.

7. **Sanity-checked the flake**: `nix eval .#nixosConfigurations.wranHearst.config.system.build.toplevel.drvPath`
   evaluates cleanly (the only host profile that includes `./sway`). The emitted
   `getExe`/nushell warning is pre-existing and unrelated.

8. **Committed** the change (`zeusOlympia/sway/swayDecl.nix`) and this `SUMMARY.md` on
   branch `dismiss-notifs-kbd`.

9. **Sent a completion `notify-send`** including the branch name.
