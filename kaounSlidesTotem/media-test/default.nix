# VM test for the media module (see ../../zeusOlympia/media/default.nix).
#
# unlike the garage/vaultwarden tests this needs no artificial secrets: the
# media module only declares services, users and (since the impermanence
# change) persistence for /srv/media and the per-service state directories.
# the machine imports the media module unchanged together with the
# impermanence module and must come up fully working:
#
#   - every service of the stack (qbittorrent, prowlarr, sonarr, radarr,
#     jellyfin, seerr, ytdl-sub timer) is active
#   - the persisted library directories exist with the ownership the module
#     used to (re)create via systemd.tmpfiles (which was removed as
#     redundant) — now created by impermanence with user/group/mode
#   - /srv/media and the service state dirs are bind-mounted from /persist
#     (i.e. they survive the host's root-on-btrfs wipe)
#   - the declarative Jellyfin accounts work: the admin `wranHearst`
#     (password `whmedia`) and the non-admin `sieyes` (password
#     `sieyesmedia`) can both authenticate through the API, wranHearst has
#     administrator rights and sieyes does not
#   - the declaratively registered Series/Movies libraries point at
#     /srv/media/tv and /srv/media/movies
#   - the Seerr bootstrap ran: Seerr is initialized, has an admin account and
#     a Sonarr + Radarr instance pointing at /srv/media/tv and
#     /srv/media/movies, and both *arrs really expose those root folders
#   - all of the above survives the reboot (persisted Seerr/Sonarr/Radarr
#     state)
#
# run with: nix build .#checks.x86_64-linux.media-vm-test
{
  pkgsLib,
  nixpkgsFlake,
  impermanenceFlake,
}:
let
  pkgs = import nixpkgsFlake { system = "x86_64-linux"; };
in
pkgs.testers.runNixOSTest {
  name = "media-stack-vm-test";

  nodes.machine =
    {
      imports = [
        impermanenceFlake.nixosModules.impermanence
        ../../zeusOlympia/media # the media module under test (incl. its impermanence + account declarations)
      ];

      networking.hostName = "mediaTestVm";

      environment.persistence."/persist".hideMounts = true;

      virtualisation = {
        graphics = false;
        memorySize = 6144;
        # jellyfin 10.11 aborts on startup when its data dir has < 2 GiB free
        diskSize = 20480;
      };
    };

  testScript = ''
    import json
    import time

    # jellyfin's JSON answers start with a UTF-8 BOM
    def load(s):
        return json.loads(s.encode("utf-8").decode("utf-8-sig"))

    # jellyfin listens on its port but answers 503 while still initializing
    # (and may even answer 200 and then restart); the retry logic below in
    # auth() handles the migration window

    def service_ok(unit):
        return machine.get_unit_info(unit)["ActiveState"] == "active"

    # ---------------------------------------------------------------
    # all services of the stack come up
    # ---------------------------------------------------------------
    for unit in [
        "qbittorrent.service",
        "prowlarr.service",
        "sonarr.service",
        "radarr.service",
        "jellyfin.service",
        "seerr.service",
    ]:
        machine.wait_for_unit(unit, timeout=300)
        assert service_ok(unit), f"{unit} not active"

    # ytdl-sub is timer-triggered; its unit must exist and be loaded
    machine.succeed("systemctl cat ytdl-sub-youtube_tv.service")

    # ---------------------------------------------------------------
    # no service of the stack may run with root privileges — not even the
    # one-shot bootstraps (media-seerr-init / media-arr-init), which run as
    # the dedicated unprivileged `media-init` user and read the *arr API keys
    # through the shared media group instead of as root.
    # ---------------------------------------------------------------
    for unit in [
        "qbittorrent.service",
        "prowlarr.service",
        "sonarr.service",
        "radarr.service",
        "jellyfin.service",
        "seerr.service",
        "ytdl-sub-youtube_tv.service",
        "media-jellyfin-init.service",
        "media-jellyfin-tree-heal.service",
        "media-seerr-init.service",
        "media-arr-init.service",
    ]:
        user = machine.succeed(f"systemctl show -p User --value {unit}").strip()
        assert user not in ("", "root"), f"{unit} runs as root ({user!r})"

    # ytdl-sub explicitly runs as its own unprivileged user
    assert (
        machine.succeed("systemctl show -p User --value ytdl-sub-youtube_tv.service").strip()
        == "ytdl-sub"
    )

    # ---------------------------------------------------------------
    # qBittorrent WebUI credentials are applied declaratively
    # (wranHearst / whmedia; the PBKDF2 secret must be stored in
    # qBittorrent's @ByteArray(base64(salt):base64(hash)) order)
    # ---------------------------------------------------------------
    machine.wait_for_open_port(8085, timeout=300)

    def qbittorrent_login():
        # wrong credentials must be rejected (401 Unauthorized)
        wrong = machine.succeed(
            "curl -sS -w '\\n%{http_code}' -X POST "
            "-H 'Referer: http://127.0.0.1:8085' "
            "--data 'username=wranHearst&password=notwhmedia' "
            "http://127.0.0.1:8085/api/v2/auth/login"
        )
        wrong_code = wrong.rsplit("\n", 1)[1].strip()
        assert wrong_code == "401", f"wrong password was not rejected: {wrong!r}"

        for _ in range(60):
            status, out = machine.execute(
                "curl -sS -w '\\n%{http_code}' -X POST "
                "-H 'Referer: http://127.0.0.1:8085' "
                "--data 'username=wranHearst&password=whmedia' "
                "http://127.0.0.1:8085/api/v2/auth/login"
            )
            if status == 0:
                body, code = out.rsplit("\n", 1)
                # 204 on qBittorrent 5.2.x, 200 + "Ok." on older versions
                if code in ("200", "204") and body.strip() in ("", "Ok."):
                    return
            time.sleep(5)
        raise AssertionError(f"qbittorrent webui login failed: {out!r}")

    qbittorrent_login()

    # ---------------------------------------------------------------
    # impermanence: /srv/media + service state must be bind mounts from
    # /persist with the ownership previously ensured by tmpfiles
    # ---------------------------------------------------------------
    mounts = machine.succeed("findmnt -rn -o TARGET,FSTYPE")
    for path in [
        "/srv/media",
        "/var/lib/qBittorrent",
        "/var/lib/sonarr",
        "/var/lib/radarr",
        "/var/lib/prowlarr",
        "/var/lib/jellyfin",
        "/var/lib/ytdl-sub",
        "/var/lib/media-init",
    ]:
        assert path in mounts, f"{path} is not a (bind) mount: {mounts}"

    expected = [
        ("/srv/media", "root:media"),
        ("/srv/media/downloads", "qbittorrent:media"),
        ("/srv/media/tv", "sonarr:media"),
        ("/srv/media/movies", "radarr:media"),
    ]
    for path, owner in expected:
        out = machine.succeed(f"stat -c '%U:%G' {path}").strip()
        assert out == owner, f"{path}: expected owner {owner}, got {out}"

    # backing dirs really live under /persist (survive a root wipe)
    for path, _ in expected:
        machine.succeed(f"test -d /persist{path}")

    # ---------------------------------------------------------------
    # declarative Jellyfin accounts
    # ---------------------------------------------------------------
    machine.wait_for_open_port(8096, timeout=300)
    # wait for the declarative setup (wizard, accounts, libraries) to finish
    machine.wait_for_unit("media-jellyfin-init.service", timeout=600)
    print("PUBLIC INFO:", machine.succeed("curl -s http://127.0.0.1:8096/System/Info/Public"))
    print("INIT UNIT:", machine.execute("systemctl status media-jellyfin-init.service --no-pager -l || true")[1])

    def auth(user, password):
        payload = (
            "-d '{\"Username\":\"%s\",\"Pw\":\"%s\"}'" % (user, password)
        )
        cmd = (
            "curl -sS -w '\\n%{http_code}' -X POST http://127.0.0.1:8096/Users/AuthenticateByName "
            "-H 'Authorization: MediaBrowser Client=\"media-test\", Device=\"media-test\", DeviceId=\"media-test\", Version=\"1.0\"' "
            "-H 'Content-Type: application/json' " + payload
        )
        # jellyfin may still be migrating/restarting even though the port is
        # open (503 + HTML, or even connection refused while it restarts);
        # retry until it answers 200 with JSON
        for _ in range(60):
            status, raw = machine.execute(cmd)
            if status != 0:
                time.sleep(5)
                continue
            body, code = raw.rsplit("\n", 1)
            if code == "200":
                return load(body)
            time.sleep(5)
        raise AssertionError(f"auth {user}: never got 200, last body={raw!r}")

    admin = auth("wranHearst", "whmedia")
    assert admin["AccessToken"], "admin authentication failed"

    user = auth("sieyes", "sieyesmedia")
    assert user["AccessToken"], "viewer authentication failed"

    # wranHearst must be admin, sieyes must not
    users_raw = machine.succeed(
        f"curl -sS -H 'Authorization: MediaBrowser Token=\"{admin['AccessToken']}\"' "
        "http://127.0.0.1:8096/Users"
    )
    print("USERS RAW:", repr(users_raw[:400]))
    users = load(users_raw)
    policies = {u["Name"]: u["Policy"]["IsAdministrator"] for u in users}
    assert policies.get("wranHearst") is True, policies
    assert policies.get("sieyes") is False, policies

    # ---------------------------------------------------------------
    # declaratively registered libraries
    # ---------------------------------------------------------------
    folders_raw = machine.succeed(
        f"curl -sS -H 'Authorization: MediaBrowser Token=\"{admin['AccessToken']}\"' "
        "http://127.0.0.1:8096/Library/VirtualFolders"
    )
    print("FOLDERS RAW:", repr(folders_raw[:400]))
    folders = load(folders_raw)
    # VirtualFolderInfo.Locations is a plain list of path strings
    byName = {v["Name"]: v["Locations"] for v in folders}
    assert byName.get("Series") == ["/srv/media/tv"], byName
    assert byName.get("Movies") == ["/srv/media/movies"], byName

    # ---------------------------------------------------------------
    # A series that was imported but never scanned must end up in Jellyfin,
    # and the Series path must end up watched for realtime updates.
    #
    # Setting EnableRealtimeMonitor on an existing library is not enough:
    # Jellyfin only (re)builds its filesystem watcher set at startup or while
    # a library scan runs, never when the options are changed through the
    # API. This was the bug: the Series library kept no watcher, so a series
    # Sonarr imported after the last scan stayed invisible until the 12h
    # scheduled scan. media-jellyfin-init now triggers a scan, which starts
    # the watchers and indexes what is already on disk.
    #
    # Reproduce that state: drop a real (valid) video into the Series
    # library and re-run the marker-guarded init, exactly as the next
    # rebuild/reboot does.
    # ---------------------------------------------------------------
    machine.succeed("mkdir -p '/srv/media/tv/Realtime Watcher Test/Season 01'")
    machine.succeed(
        "${pkgs.jellyfin-ffmpeg}/bin/ffmpeg -nostdin -loglevel error "
        "-f lavfi -i color=c=black:s=128x72:d=1 -c:v libx264 -pix_fmt yuv420p "
        "'/srv/media/tv/Realtime Watcher Test/Season 01/Realtime Watcher Test S01E01.mkv'"
    )

    machine.succeed("rm -f /var/lib/jellyfin/config/.nixos-media-users-created-v3")
    machine.succeed("systemctl restart media-jellyfin-init.service")
    machine.wait_for_unit("media-jellyfin-init.service", timeout=600)

    # the scan the init triggered must have started the watcher on the
    # Series path (this is what was missing and is what makes later imports
    # appear without a manual scan)
    machine.wait_until_succeeds(
        "grep -Rqs 'Watching directory \"/srv/media/tv\"' /var/lib/jellyfin/log/",
        timeout=300,
    )

    # ...and indexed the episode, so the series shows up in Jellyfin
    def series_names():
        items = load(machine.succeed(
            f"curl -sS -H 'Authorization: MediaBrowser Token=\"{admin['AccessToken']}\"' "
            "'http://127.0.0.1:8096/Items?Recursive=true&IncludeItemTypes=Series'"
        ))
        return [i.get("Name") or "" for i in items["Items"]]

    for _ in range(90):
        if any("realtime watcher test" in n.lower() for n in series_names()):
            break
        time.sleep(5)
    else:
        raise AssertionError(
            "the imported series was not indexed by Jellyfin's scan: %r"
            % series_names()
        )

    # ---------------------------------------------------------------
    # the series -> seasons -> episodes tree must survive. Jellyfin can
    # end up with series whose child queries (/Shows/{id}/Seasons,
    # /Shows/{id}/Episodes) return empty even though the Season/Episode
    # items exist with correct ParentId/SeriesId links; the web client
    # then fails every series playback with "unable to find valid media
    # source to play" (its episode queueing uses exactly that query).
    # media-jellyfin-tree-heal detects the empty query and heals the
    # series with a recursive refresh. Re-run the unit here (it also
    # runs on every boot) and require the episode queue to be present.
    # ---------------------------------------------------------------
    machine.succeed("systemctl restart media-jellyfin-tree-heal.service")
    machine.wait_for_unit("media-jellyfin-tree-heal.service", timeout=300)
    machine.succeed("systemctl is-active media-jellyfin-tree-heal.service")

    def series_episode_counts():
        items = load(machine.succeed(
            f"curl -sS -H 'Authorization: MediaBrowser Token=\"{admin['AccessToken']}\"' "
            "'http://127.0.0.1:8096/Items?Recursive=true&IncludeItemTypes=Series'"
        ))["Items"]
        out = {}
        for s in items:
            res = load(machine.succeed(
                f"curl -sS -H 'Authorization: MediaBrowser Token=\"{admin['AccessToken']}\"' "
                f"'http://127.0.0.1:8096/Shows/{s['Id']}/Episodes'"
            ))
            out[s["Name"]] = len(res.get("Items", []))
        return out

    counts = series_episode_counts()
    print("SERIES EPISODE COUNTS:", counts)
    empty = {n: c for n, c in counts.items() if c == 0}
    assert not empty, (
        "series with a broken seasons/episodes tree after "
        "media-jellyfin-tree-heal: %r" % empty
    )

    # ---------------------------------------------------------------
    # playback, end to end: Jellyfin (unprivileged, only in the media group)
    # must actually read the file off disk and serve it — indexing it is not
    # enough. This is the user-facing "press play" path.
    # ---------------------------------------------------------------
    episodes = load(machine.succeed(
        f"curl -sS -H 'Authorization: MediaBrowser Token=\"{admin['AccessToken']}\"' "
        "'http://127.0.0.1:8096/Items?Recursive=true&IncludeItemTypes=Episode'"
    ))["Items"]
    e2e_eps = [
        e for e in episodes
        if "realtime watcher test" in (e.get("SeriesName") or "").lower()
    ]
    assert e2e_eps, [e.get("SeriesName") for e in episodes]
    e2e_id = e2e_eps[0]["Id"]
    served = machine.succeed(
        f"curl -sS -o /dev/null -w '%{{http_code}} %{{size_download}}' "
        f"-r 0-1023 -H 'Authorization: MediaBrowser Token=\"{admin['AccessToken']}\"' "
        f"'http://127.0.0.1:8096/Videos/{e2e_id}/stream?static=true&api_key={admin['AccessToken']}'"
    ).strip()
    served_code, served_bytes = served.split()
    assert served_code in ("200", "206"), f"jellyfin could not serve the file: {served!r}"
    assert int(served_bytes) > 0, f"jellyfin served an empty file: {served!r}"

    # ---------------------------------------------------------------
    # seerr is reachable and its declarative Radarr/Sonarr integration is
    # in place (media-seerr-init finished the setup wizard and registered
    # both *arrs; the *arrs have the root folders Seerr points at)
    # ---------------------------------------------------------------
    machine.wait_for_open_port(5055, timeout=300)
    machine.succeed("curl -sf http://127.0.0.1:5055/ -o /dev/null")

    machine.wait_for_unit("media-seerr-init.service", timeout=900)
    assert service_ok("media-seerr-init.service"), "media-seerr-init not active"

    public = load(machine.succeed("curl -sS http://127.0.0.1:5055/api/v1/settings/public"))
    assert public.get("initialized") is True, public

    def seerr_login():
        # Seerr is already configured by media-seerr-init, so the Jellyfin
        # hostname must not be sent again (only credentials).
        for _ in range(60):
            status, _out = machine.execute(
                "curl -sS -f -c /tmp/seerr.cookies -X POST "
                "-H 'Content-Type: application/json' "
                "-d '{\"username\":\"wranHearst\",\"password\":\"whmedia\"}' "
                "http://127.0.0.1:5055/api/v1/auth/jellyfin"
            )
            if status == 0:
                return
            time.sleep(5)
        raise AssertionError("seerr login failed")

    seerr_login()

    sonarr = load(machine.succeed(
        "curl -sS -b /tmp/seerr.cookies http://127.0.0.1:5055/api/v1/settings/sonarr"
    ))
    radarr = load(machine.succeed(
        "curl -sS -b /tmp/seerr.cookies http://127.0.0.1:5055/api/v1/settings/radarr"
    ))
    print("SEERR SONARR:", sonarr)
    print("SEERR RADARR:", radarr)
    assert len(sonarr) == 1, sonarr
    assert len(radarr) == 1, radarr
    assert sonarr[0]["hostname"] == "127.0.0.1" and sonarr[0]["port"] == 8989
    assert sonarr[0]["activeDirectory"] == "/srv/media/tv", sonarr
    assert sonarr[0]["isDefault"] is True and sonarr[0]["apiKey"], sonarr
    assert radarr[0]["hostname"] == "127.0.0.1" and radarr[0]["port"] == 7878
    assert radarr[0]["activeDirectory"] == "/srv/media/movies", radarr
    assert radarr[0]["isDefault"] is True and radarr[0]["apiKey"], radarr
    assert radarr[0]["minimumAvailability"] == "released", radarr

    # the *arrs really have the root folders Seerr points at
    sonarr_key = machine.succeed(
        "sed -n 's:.*<ApiKey>\\([^<]*\\)</ApiKey>.*:\\1:p' "
        "/var/lib/sonarr/.config/NzbDrone/config.xml | head -n1"
    ).strip()
    radarr_key = machine.succeed(
        "sed -n 's:.*<ApiKey>\\([^<]*\\)</ApiKey>.*:\\1:p' "
        "/var/lib/radarr/.config/Radarr/config.xml | head -n1"
    ).strip()
    sonarr_folders = load(machine.succeed(
        f"curl -sS -H 'X-Api-Key: {sonarr_key}' http://127.0.0.1:8989/api/v3/rootfolder"
    ))
    radarr_folders = load(machine.succeed(
        f"curl -sS -H 'X-Api-Key: {radarr_key}' http://127.0.0.1:7878/api/v3/rootfolder"
    ))
    assert any(f["path"] == "/srv/media/tv" for f in sonarr_folders), sonarr_folders
    assert any(f["path"] == "/srv/media/movies" for f in radarr_folders), radarr_folders

    # ---------------------------------------------------------------
    # media-arr-init wired up the download chain declaratively: qBittorrent
    # is the download client of both *arrs, Prowlarr knows both *arrs as
    # applications and has a public indexer, which Prowlarr then pushed to
    # the *arrs as a Torznab indexer. Without this an approved Seerr request
    # was added to Radarr/Sonarr but never searched ("0 active indexers") and
    # never reached qBittorrent/Jellyfin.
    # ---------------------------------------------------------------
    machine.wait_for_unit("media-arr-init.service", timeout=900)
    assert service_ok("media-arr-init.service"), "media-arr-init not active"

    for key, port, catfield, cat in [
        (sonarr_key, 8989, "tvCategory", "sonarr"),
        (radarr_key, 7878, "movieCategory", "radarr"),
    ]:
        clients = load(machine.succeed(
            f"curl -sS -H 'X-Api-Key: {key}' "
            f"http://127.0.0.1:{port}/api/v3/downloadclient"
        ))
        qb = [c for c in clients if c["implementation"] == "QBittorrent"]
        assert len(qb) == 1, clients
        assert qb[0]["enable"] is True, qb
        fields = {f["name"]: f.get("value") for f in qb[0]["fields"]}
        assert fields.get("host") == "127.0.0.1", fields
        assert fields.get("port") == 8085, fields
        assert fields.get(catfield) == cat, fields

    prowlarr_key = machine.succeed(
        "sed -n 's:.*<ApiKey>\\([^<]*\\)</ApiKey>.*:\\1:p' "
        "/var/lib/prowlarr/config.xml | head -n1"
    ).strip()
    prowlarr_apps = load(machine.succeed(
        f"curl -sS -H 'X-Api-Key: {prowlarr_key}' "
        "http://127.0.0.1:9696/api/v1/applications"
    ))
    assert {a["name"] for a in prowlarr_apps} == {"Sonarr", "Radarr"}, prowlarr_apps
    # (the public indexer(s) from `prowlarrIndexers` are also registered and
    # pushed to the *arrs as Torznab indexers, but Prowlarr fetches its
    # Cardigann definitions from indexers.prowlarr.com, which is not reachable
    # from the offline test VM, so that part is not asserted here. It was
    # verified against the real stack, where the definitions are present.)

    # ---------------------------------------------------------------
    # the stored wiring must actually *work*, not merely exist: the *arrs
    # have to reach qBittorrent with the configured credentials, and Prowlarr
    # has to reach both *arrs. A client that is stored but unreachable is
    # exactly the kind of curb an over-restrictive unprivileged setup could
    # introduce, and the config-inspection checks above would not catch it.
    # ---------------------------------------------------------------
    for key, port in [(sonarr_key, 8989), (radarr_key, 7878)]:
        results = load(machine.succeed(
            f"curl -sS -X POST -H 'X-Api-Key: {key}' "
            f"-H 'Content-Type: application/json' -d '{{}}' "
            f"http://127.0.0.1:{port}/api/v3/downloadclient/testall"
        ))
        assert results and all(r["isValid"] for r in results), (port, results)

    app_tests = load(machine.succeed(
        f"curl -sS -X POST -H 'X-Api-Key: {prowlarr_key}' "
        "-H 'Content-Type: application/json' -d '{}' "
        "http://127.0.0.1:9696/api/v1/applications/testall"
    ))
    assert app_tests and all(r["isValid"] for r in app_tests), app_tests

    # ---------------------------------------------------------------
    # END-TO-END PERMISSIONS: prove every unprivileged service can do its
    # real job on the shared /srv/media tree. The checks above only prove the
    # units are up and wired; a wrong owner/group/UMask would still let them
    # start. This is what actually guarantees the stack is usable with no
    # root anywhere in the loop.
    # ---------------------------------------------------------------
    # qbittorrent downloads (umask 0002, like the real unit) ...
    machine.succeed(
        "runuser -u qbittorrent -- sh -c "
        "'umask 0002; printf download > /srv/media/downloads/.e2e-dl'"
    )
    # ... sonarr imports it into the TV library (a move: needs group write on
    # the download file and on the target directory) ...
    machine.succeed(
        "runuser -u sonarr -- sh -c "
        "'umask 0002; mv /srv/media/downloads/.e2e-dl /srv/media/tv/.e2e-dl'"
    )
    # ... and jellyfin reads what sonarr wrote
    machine.succeed("runuser -u jellyfin -- cat /srv/media/tv/.e2e-dl >/dev/null")

    # the same chain for movies (qbittorrent -> radarr -> jellyfin)
    machine.succeed(
        "runuser -u qbittorrent -- sh -c "
        "'umask 0002; printf download > /srv/media/downloads/.e2e-dl2'"
    )
    machine.succeed(
        "runuser -u radarr -- sh -c "
        "'umask 0002; mv /srv/media/downloads/.e2e-dl2 /srv/media/movies/.e2e-dl2'"
    )
    machine.succeed("runuser -u jellyfin -- cat /srv/media/movies/.e2e-dl2 >/dev/null")

    # ytdl-sub writes straight into the TV library
    machine.succeed(
        "runuser -u ytdl-sub -- sh -c 'umask 0002; printf yt > /srv/media/tv/.e2e-ytdl'"
    )
    machine.succeed("runuser -u jellyfin -- cat /srv/media/tv/.e2e-ytdl >/dev/null")

    # the unprivileged bootstrap can read the *arr API keys (the reason it
    # used to need root) and owns its marker directory
    for keyfile in [
        "/var/lib/sonarr/.config/NzbDrone/config.xml",
        "/var/lib/radarr/.config/Radarr/config.xml",
        "/var/lib/prowlarr/config.xml",
    ]:
        machine.succeed(f"runuser -u media-init -- cat {keyfile} >/dev/null")
    machine.succeed("runuser -u media-init -- sh -c 'touch /var/lib/media-init/.e2e-marker'")

    # both bootstraps really used the new, unprivileged marker location
    for marker in [
        ".nixos-media-seerr-configured",
        ".nixos-media-arr-configured",
    ]:
        machine.succeed(f"test -f /var/lib/media-init/{marker}")

    machine.succeed(
        "rm -f /srv/media/downloads/.e2e-dl /srv/media/downloads/.e2e-dl2 "
        "/srv/media/tv/.e2e-dl /srv/media/tv/.e2e-ytdl "
        "/srv/media/movies/.e2e-dl2 /var/lib/media-init/.e2e-marker"
    )

    # ---------------------------------------------------------------
    # persistence: reboot and confirm everything survives (on wranHearst
    # the root btrfs subvolume is wiped on every boot, so this is what the
    # /persist declarations are for)
    # ---------------------------------------------------------------
    machine.shutdown()
    # fresh boot on the same disk: exactly what a wranHearst reboot looks
    # like (root wiped by the rollback service in the real setup, state
    # taken from /persist)
    machine.start()
    machine.wait_for_unit("multi-user.target", timeout=600)
    machine.wait_for_unit("jellyfin.service", timeout=600)
    machine.wait_for_unit("media-jellyfin-init.service", timeout=600)
    machine.wait_for_open_port(8096, timeout=300)

    # ownership of the library dirs is still correct after the reboot
    # (impermanence must not have recreated them with default perms and the
    # tmpfiles re-assert must have kept them right)
    for path, owner in expected:
        out = machine.succeed(f"stat -c '%U:%G' {path}").strip()
        assert out == owner, f"after reboot {path}: expected {owner}, got {out}"

    # the declarative users are still there (the init unit exits early via
    # its marker file, so this proves they were persisted)
    admin2 = auth("wranHearst", "whmedia")
    assert admin2["AccessToken"], "admin auth failed after reboot"
    user2 = auth("sieyes", "sieyesmedia")
    assert user2["AccessToken"], "viewer auth failed after reboot"

    # libraries are still registered
    folders2 = load(machine.succeed(
        f"curl -sS -H 'Authorization: MediaBrowser Token=\"{admin2['AccessToken']}\"' "
        "http://127.0.0.1:8096/Library/VirtualFolders"
    ))
    byName2 = {v["Name"]: v["Locations"] for v in folders2}
    assert byName2.get("Series") == ["/srv/media/tv"], byName2
    assert byName2.get("Movies") == ["/srv/media/movies"], byName2

    # the qBittorrent download client wiring survived the reboot (media-arr-init
    # exits early via its persisted marker file, so this proves persistence)
    machine.wait_for_unit("media-arr-init.service", timeout=900)
    for key, port in [(sonarr_key, 8989), (radarr_key, 7878)]:
        clients2 = load(machine.succeed(
            f"curl -sS -H 'X-Api-Key: {key}' "
            f"http://127.0.0.1:{port}/api/v3/downloadclient"
        ))
        assert any(c["implementation"] == "QBittorrent" for c in clients2), clients2

    # the Seerr Radarr/Sonarr integration survived the reboot (the bootstrap
    # unit exits early via its persisted marker file, so this proves the
    # configuration was persisted)
    machine.wait_for_unit("media-seerr-init.service", timeout=900)
    public2 = load(machine.succeed("curl -sS http://127.0.0.1:5055/api/v1/settings/public"))
    assert public2.get("initialized") is True, public2
    seerr_login()
    sonarr2 = load(machine.succeed(
        "curl -sS -b /tmp/seerr.cookies http://127.0.0.1:5055/api/v1/settings/sonarr"
    ))
    radarr2 = load(machine.succeed(
        "curl -sS -b /tmp/seerr.cookies http://127.0.0.1:5055/api/v1/settings/radarr"
    ))
    assert len(sonarr2) == 1 and sonarr2[0]["activeDirectory"] == "/srv/media/tv", sonarr2
    assert len(radarr2) == 1 and radarr2[0]["activeDirectory"] == "/srv/media/movies", radarr2
  '';
}
