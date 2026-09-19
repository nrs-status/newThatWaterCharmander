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
