# Fix: only one of three YouTube channels appears in Jellyfin

Git branch: `fix-ytdl-sub`

## Symptom

`zeusOlympia/media/default.nix` subscribes ytdl-sub to three YouTube channels
(`ThePrimeTimeagen`, `Pezle`, `Mr. Beat`), but only `ThePrimeTimeagen` ever
showed up in Jellyfin (i.e. only one show directory existed in `/srv/media/tv`).

## Root cause

`ytdl-sub-youtube_tv.service` was in a failed state. The journal showed, on
every 6-hourly run:

```
ytdl-sub[262783]: [ytdl-sub] ytdl-sub does not have write permissions to the output directory: /srv/media/tv/ThePrimeTimeagen
systemd[1]: ytdl-sub-youtube_tv.service: Main process exited, code=exited, status=1/FAILURE
```

`ytdl-sub` validates that it can write to **every** subscription's show
directory *before* downloading anything, and aborts the entire run on the
first failure. The show directory `/srv/media/tv/ThePrimeTimeagen` was left
over from an earlier configuration and was owned by `seerr:media` with mode
`0755`, so the service user `ytdl-sub` (primary group `media`) had no write
access. Because the run aborted during validation, neither `Pezle` nor
`Mr. Beat` was ever downloaded, even though their subscription URLs (and the
whole preset) were perfectly valid.

Host state confirming this:

```
$ stat -c '%U:%G %a %n' /srv/media/tv /srv/media/tv/ThePrimeTimeagen
sonarr:media 775 /srv/media/tv
seerr:media  755 /srv/media/tv/ThePrimeTimeagen
```

## Steps taken

1. **Read `instructions.txt`** and explored the repo
   (`zeusOlympia/media/default.nix`, the media module, and the existing
   `kaounSlidesTotem/media-test` VM test harness).
2. **Diagnosed from the machine, not from the config**: checked
   `systemctl status ytdl-sub-youtube_tv.service` and `journalctl -u
   ytdl-sub-youtube_tv.service`, which revealed the run was failing, and
   `stat` on the library, which revealed the stale `seerr:media 0755` show
   directory.
3. **Validated the subscription configuration itself was fine** by running
   the real store config/subscriptions through `ytdl-sub --dry-run` (output
   redirected to `/tmp`): all three channels passed validation and began
   their dry runs (`Beginning subscription dry run for Mr. Beat`, `... for
   Pezle`, `... for ThePrimeTimeagen`). So the only problem was permissions.
4. **First fix attempt**: per-subscription
   `systemd.tmpfiles.settings."10-media-ytdl-sub"` rules with `Z`
   (`chown -R ytdl-sub:media`) generated from the subscription list.
5. **The VM test caught a flaw in that approach**: systemd-tmpfiles refuses
   to operate on a target when walking to it crosses an ownership change
   between two non-root users —
   `Detected unsafe path transition /srv/media/tv (owned by sonarr) →
   /srv/media/tv/Pezle (owned by seerr) during canonicalization` (exit 73).
   This is the *exact* stale state to heal, and even a healthy
   ytdl-sub-owned show directory under the sonarr-owned library root would
   hit the same guard. So per-directory rules can never work here.
6. **Final fix** in `zeusOlympia/media/default.nix`: one recursive
   `systemd.tmpfiles` rule on the library root itself, which is reachable
   (root-owned parents → sonarr-owned root is an allowed transition) and
   whose recursive walk applies permissions to the whole tree without
   per-entry safety checks:

   ```
   systemd.tmpfiles.settings."10-media-ytdl-sub"."/srv/media/tv".Z = {
     mode = "0775";
     user = "-";            # ownership is left alone
     group = mediaGroup;    # everything group-writable for the media group
   };
   ```

   Rendered rule (verified by building the host toplevel):

   ```
   'Z' '/srv/media/tv' '0775' '-' 'media' '-'
   ```

   This heals the stale `seerr`-owned show directory on the next
   `nixos-rebuild switch` (which runs `systemd-tmpfiles --create`) and on
   every boot, so ytdl-sub can always write into every subscription's show
   directory and the download run no longer aborts during validation.

7. **Regression test** added to `kaounSlidesTotem/media-test/default.nix`
   (media VM test): it re-asserts the rendered `10-media-ytdl-sub.conf`
   contains the rule, recreates the exact broken state (a show directory
   owned by `seerr:media` with `0755`), asserts ytdl-sub *cannot* write to it
   before the heal, runs `systemd-tmpfiles --create 10-media-ytdl-sub.conf`
   (what a rebuild/boot does), asserts the directory became group
   `media` and group-writable while the library root owner stayed `sonarr`,
   and finally asserts ytdl-sub can extend the existing episode file,
   create `Season 2025/episode2.mp4` and rewrite its
   `.ytdl-sub-Pezle-download-archive.json` — i.e. exactly what a real
   download run does.

## Testing / verification

- `nix build -L --rebuild .#checks.x86_64-linux.media-vm-test` → **exit 0**
  (full media-stack VM test, including the new regression section; the test
  failed at first, which is how the tmpfiles unsafe-transition guard was
  discovered).
- The regression section log shows:
  `must fail: runuser -u ytdl-sub ... Permission denied`, then
  `must succeed: systemd-tmpfiles --create 10-media-ytdl-sub.conf`, then the
  ytdl-sub write/create commands succeeding.
- `nix build .#nixosConfigurations.wranHearst.config.system.build.toplevel`
  succeeds and `etc/tmpfiles.d/10-media-ytdl-sub.conf` contains the expected
  `Z /srv/media/tv 0775 - media -` rule.
- Host dry-run of the real subscription file proved all three channel URLs
  and the preset validate.

## Note on applying the fix to the live host (wranHearst)

The task environment explicitly has **no root privileges** (`sudo` requires a
password, no `pkexec`, no root SSH key), and the live directory is owned by
`seerr` so it cannot be repaired from an unprivileged account. The fix is
therefore implemented declaratively: the next administrator-run
`nixos-rebuild switch` (or reboot) will run the new `systemd-tmpfiles` rule,
heal `/srv/media/tv` to `group=media, mode=0775`, and the next
`ytdl-sub-youtube_tv.timer` tick (every 6 hours, or a manual
`systemctl start ytdl-sub-youtube_tv`) will download `Pezle` and `Mr. Beat`
alongside `ThePrimeTimeagen` — all three then appear in Jellyfin's Series
library automatically.

## Files changed

- `zeusOlympia/media/default.nix` — declarative self-healing tmpfiles rule.
- `kaounSlidesTotem/media-test/default.nix` — regression test for the exact
  stale-permission failure mode.

`instructions.txt` is untracked but was pre-existing in the working tree.
No changes were committed (as requested).
