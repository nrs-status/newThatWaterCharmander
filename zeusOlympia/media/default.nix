# Media stack for wranHearst:
#   qBittorrent (downloads) -> Prowlarr (indexer management) ->
#   Sonarr (TV) / Radarr (movies) -> Jellyfin (playback) with
#   Jellyseerr (requests) on top,
#   + ytdl-sub: YouTube channels downloaded directly into the TV library
#     as TV shows (via the "Jellyfin TV Show by Date" preset, which writes
#     NFO metadata, posters and fanart that Jellyfin reads natively).
#
# layout: qBittorrent saves to /srv/media/downloads, Sonarr/Radarr import
# from there into /srv/media/tv and /srv/media/movies, Jellyfin serves
# /srv/media. all of the service users share the "media" group so the
# download -> import -> serve chain works without permission friction
# (hence the 0002 umasks and group-writable directories below).
#
# wranHearst runs impermanence (root is wiped on reboot, see
# ../fs/impermanence.nix), so all of the stack's state (media library +
# service state dirs) is persisted under /persist explicitly (see the
# bottom of the file).
#
# the Jellyfin accounts (admin `wranHearst`, viewer `sieyes`) and the
# TV/movie libraries are set up declaratively by media-jellyfin-init.service
# on first boot (the passwords live in this file, since Jellyfin offers no
# declarative user-management option in nixpkgs).
#
# the connection from an approved Seerr request to an actual download is set
# up declaratively too: media-seerr-init registers Sonarr/Radarr in Seerr and
# media-arr-init gives both *arrs a qBittorrent download client plus a
# Prowlarr-backed indexer (see the comments on those services), so requests
# reach qBittorrent and, once imported, Jellyfin without manual setup.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  mediaRoot = "/srv/media";
  mediaGroup = "media";

  # Jellyfin administrator created by media-jellyfin-init; the Seerr
  # bootstrap signs in with the same account (it is the only Jellyfin admin
  # at that point).
  jellyfinAdminUser = "wranHearst";
  jellyfinAdminPassword = "whmedia";

  # qBittorrent WebUI credentials, reused for the *arr download client below
  # (the WebUI password is stored as a precomputed PBKDF2 hash in
  # services.qbittorrent.serverConfig further down; the plaintext hash source
  # is kept in sync with these variables by hand).
  qbittorrentUser = jellyfinAdminUser;
  qbittorrentPassword = jellyfinAdminPassword;

  # Public trackers (Prowlarr definition names) that media-arr-init adds on
  # first boot. These need no account, so the request -> download chain works
  # out of the box; private/credentialed indexers are still added by an admin
  # in the Prowlarr UI. Add to this list to seed more indexers declaratively.
  prowlarrIndexers = [ "thepiratebay" ];

  # completes Jellyfin's first-boot setup wizard declaratively and creates
  # the two service accounts (see the comment on the unit below).
  # The whole flow is retried until a deadline: Jellyfin restarts internally
  # while running its DB migrations (its web server answers 503/HTML while
  # starting, and even 200-then-503 in quick succession), so single-shot
  # attempts are too fragile.
  jellyfinInit = pkgs.writeShellScript "media-jellyfin-init" ''
    set -uo pipefail

    base=http://127.0.0.1:8096
    # v3: bumped again because enabling EnableRealtimeMonitor on an existing
    # library is not enough on its own. Jellyfin (re)builds its filesystem
    # watcher set when a library scan runs (and at startup), *not* when the
    # library options are updated through the API, so after the v2 run the
    # Series library still had no watcher and newly imported episodes stayed
    # invisible until the 12h scheduled scan. The v3 run re-executes the
    # script, which now also triggers a library scan (see the refresh at the
    # end of run_flow) so the watcher is actually started.
    marker=${config.services.jellyfin.configDir}/.nixos-media-users-created-v3
    curl=${lib.getExe pkgs.curl}
    jq=${lib.getExe pkgs.jq}
    sleep=${lib.getExe' pkgs.coreutils "sleep"}
    touch=${lib.getExe' pkgs.coreutils "touch"}
    seq=${lib.getExe' pkgs.coreutils "seq"}
    date=${lib.getExe' pkgs.coreutils "date"}
    grep=${lib.getExe pkgs.gnugrep}
    authHeader='Authorization: MediaBrowser Client="nixos-media", Device="nixos-media", DeviceId="nixos-media", Version="1.0"'

    [ -f "$marker" ] && exit 0

    run_flow() (
      set -euo pipefail

      # wait until Jellyfin answers a *valid* public info response (its web
      # server is up early but answers 503/HTML while migrating)
      ready=""
      for i in $($seq 1 150); do
        if out=$($curl -fsS "$base/System/Info/Public" 2>/dev/null) \
          && echo "$out" | $jq -e 'has("StartupWizardCompleted")' >/dev/null 2>&1; then
          ready=1
          break
        fi
        $sleep 2
      done
      if [ -z "$ready" ]; then
        echo "media-jellyfin-init: Jellyfin did not become ready in time" >&2
        return 1
      fi

      wizardCompleted=$($curl -fsS "$base/System/Info/Public" | $jq -r '.StartupWizardCompleted // false')
      fresh=0
      if [ "$wizardCompleted" != "true" ]; then
        # finish the first-boot setup wizard: the user created here becomes
        # the administrator. GET /Startup/User first: on a fresh database no
        # user exists yet, and POST /Startup/User only *updates* the first
        # user (renaming it + setting the password) — it is the GET that
        # triggers the manager's InitializeAsync, which seeds the placeholder
        # first user
        $curl -fsS -X POST "$base/Startup/Configuration" \
          -H 'Content-Type: application/json' \
          -d '{"UICulture":"en-US","MetadataCountryCode":"US","PreferredMetadataLanguage":"en"}'
        $curl -fsS "$base/Startup/User" >/dev/null
        $curl -fsS -X POST "$base/Startup/User" \
          -H 'Content-Type: application/json' \
          -d '{"Name":"${jellyfinAdminUser}","Password":"${jellyfinAdminPassword}"}'
        $curl -fsS -X POST "$base/Startup/Complete"
        fresh=1
      fi

      # authenticate the admin account so we can manage users/libraries
      token=$($curl -fsS -X POST "$base/Users/AuthenticateByName" \
        -H "$authHeader" -H 'Content-Type: application/json' \
        -d '{"Username":"${jellyfinAdminUser}","Pw":"${jellyfinAdminPassword}"}' | $jq -r '.AccessToken // empty') || token=""
      if [ -z "$token" ]; then
        if [ "$fresh" = 1 ]; then
          echo "media-jellyfin-init: could not authenticate the just-created admin user" >&2
          return 1
        fi
        echo "media-jellyfin-init: wizard already completed and the configured admin" >&2
        echo "password was rejected (changed outside this configuration?); skipping" >&2
        return 0
      fi
      apiHeader="Authorization: MediaBrowser Token=\"$token\""

      # non-admin account for regular viewers (created with the default
      # policy, i.e. no administrator rights)
      if ! $curl -fsS -H "$apiHeader" "$base/Users" | $jq -r '.[].Name' | $grep -qx sieyes; then
        $curl -fsS -X POST "$base/Users/New" -H "$apiHeader" \
          -H 'Content-Type: application/json' \
          -d '{"Name":"sieyes","Password":"sieyesmedia"}'
      fi

      # make sure the library folders exist and notice new files promptly.
      # Realtime monitoring is enabled so a file imported by Sonarr/Radarr
      # appears in Jellyfin within seconds instead of waiting for the (12h)
      # scheduled library scan; existing libraries are updated in place,
      # because a rebuild has to fix installs whose libraries were created
      # before EnableRealtimeMonitor was set.
      # Enabling the option is not sufficient by itself: Jellyfin only starts
      # the matching file watchers during a library scan (or at startup), so
      # run_flow triggers a scan after creating/updating the libraries (see
      # below).
      folders=$($curl -fsS -H "$apiHeader" "$base/Library/VirtualFolders") || folders=""
      ensure_library() {
        local name=$1 collection=$2 path=$3
        local folder id options
        folder=$(printf '%s' "$folders" | $jq -c --arg n "$name" '[.[] | select(.Name == $n)][0]')
        if [ -z "$folder" ] || [ "$folder" = "null" ]; then
          $curl -fsS -X POST "$base/Library/VirtualFolders?name=$name&collectionType=$collection" \
            -H "$apiHeader" -H 'Content-Type: application/json' \
            -d "$($jq -n --arg p "$path" '{LibraryOptions:{EnableRealtimeMonitor:true,PathInfos:[{Path:$p}]}}')"
          return
        fi
        if [ "$(printf '%s' "$folder" | $jq -r '.LibraryOptions.EnableRealtimeMonitor // false')" = "true" ]; then
          return
        fi
        id=$(printf '%s' "$folder" | $jq -r '.ItemId')
        options=$(printf '%s' "$folder" | $jq -c '.LibraryOptions')
        $jq -n --arg id "$id" --argjson opts "$options" \
          '{Id:$id, LibraryOptions:($opts + {EnableRealtimeMonitor:true})}' \
          | $curl -fsS -X POST "$base/Library/VirtualFolders/LibraryOptions" \
              -H "$apiHeader" -H 'Content-Type: application/json' --data @-
      }
      ensure_library Series tvshows "${mediaRoot}/tv"
      ensure_library Movies movies "${mediaRoot}/movies"

      # Trigger a library scan now. Two reasons:
      #   1. it indexes anything already present in the library (so media
      #      imported before the first scheduled scan shows up immediately),
      #   2. Jellyfin (re)creates its filesystem watchers during/after a scan,
      #      which is what makes EnableRealtimeMonitor take effect. Changing
      #      the library options through the API alone does not start a
      #      watcher, which is exactly why existing installs kept missing
      #      newly imported episodes.
      $curl -fsS -X POST -H "$apiHeader" "$base/Library/Refresh" >/dev/null
    )

    # retry until a deadline (jellyfin keeps restarting while migrating on a
    # fresh boot); every step is guarded/idempotent, so retrying is safe
    deadline=$(( $($date +%s) + 600 ))
    while true; do
      if run_flow; then
        $touch "$marker"
        exit 0
      fi
      if [ "$( $date +%s )" -ge "$deadline" ]; then
        echo "media-jellyfin-init: giving up after 10 minutes" >&2
        exit 1
      fi
      $sleep 5
    done
  '';

  # Declarative Seerr bootstrap. On first boot it:
  #   1. waits for Sonarr/Radarr, reads their (self-generated) API keys from
  #      their config.xml, makes sure the /srv/media/tv and /srv/media/movies
  #      root folders exist and picks a quality profile,
  #   2. signs in to Seerr with the Jellyfin admin account created by
  #      media-jellyfin-init (the first login also creates Seerr's admin user
  #      and configures the Jellyfin connection),
  #   3. completes the Seerr setup wizard and registers the Sonarr and Radarr
  #      instances so requests from the Seerr UI work immediately.
  # Like media-jellyfin-init it is idempotent (every step checks state first)
  # and guarded by a marker file in the persisted Seerr config dir, and it
  # retries until a deadline because all three services may still be starting
  # or migrating on a fresh boot.
  seerrInit = pkgs.writeShellScript "media-seerr-init" ''
    set -uo pipefail

    seerrBase=http://127.0.0.1:5055
    sonarrBase=http://127.0.0.1:8989
    radarrBase=http://127.0.0.1:7878
    marker=${config.services.seerr.configDir}/.nixos-media-seerr-configured

    curl=${lib.getExe pkgs.curl}
    jq=${lib.getExe pkgs.jq}
    sleep=${lib.getExe' pkgs.coreutils "sleep"}
    touch=${lib.getExe' pkgs.coreutils "touch"}
    seq=${lib.getExe' pkgs.coreutils "seq"}
    date=${lib.getExe' pkgs.coreutils "date"}
    mktemp=${lib.getExe' pkgs.coreutils "mktemp"}
    rm=${lib.getExe' pkgs.coreutils "rm"}
    head=${lib.getExe' pkgs.coreutils "head"}
    tail=${lib.getExe' pkgs.coreutils "tail"}
    sed=${lib.getExe pkgs.gnused}

    [ -f "$marker" ] && exit 0

    # wait for a config.xml to appear and yield the *arr API key it contains
    read_api_key() {
      local file=$1 key
      for _ in $($seq 1 300); do
        if [ -f "$file" ]; then
          key=$($sed -n 's:.*<ApiKey>\([^<]*\)</ApiKey>.*:\1:p' "$file" | $head -n1)
          if [ -n "$key" ]; then
            printf '%s' "$key"
            return 0
          fi
        fi
        $sleep 2
      done
      return 1
    }

    # create the *arr root folder if it is missing
    ensure_root_folder() {
      local base=$1 key=$2 path=$3 folders
      folders=$($curl -fsS -H "X-Api-Key: $key" "$base/api/v3/rootfolder")
      if ! printf '%s' "$folders" | $jq -e --arg p "$path" 'any(.[]; .path == $p)' >/dev/null; then
        $jq -n --arg p "$path" '{path:$p}' \
          | $curl -fsS -X POST -H "X-Api-Key: $key" -H 'Content-Type: application/json' --data @- "$base/api/v3/rootfolder" >/dev/null
      fi
    }

    # print "<id>\t<name>" of the preferred quality profile (falls back to
    # the first one when the usual names are absent)
    pick_profile() {
      local base=$1 key=$2
      $curl -fsS -H "X-Api-Key: $key" "$base/api/v3/qualityprofile" \
        | $jq -r '([.[] | select(.name == "HD-1080p")][0]) // ([.[] | select(.name == "Any")][0]) // .[0] | if . == null then empty else "\(.id)\t\(.name)" end'
    }

    # create or update the Seerr Sonarr/Radarr instance (so a partially
    # finished run converges instead of duplicating the entry)
    configure_dvr() {
      local kind=$1 body=$2 existing id
      existing=$($curl -fsS -b "$cookieJar" "$seerrBase/api/v1/settings/$kind")
      id=$(printf '%s' "$existing" | $jq -r '.[0].id // empty')
      if [ -z "$id" ]; then
        printf '%s' "$body" | $curl -fsS -b "$cookieJar" -X POST -H 'Content-Type: application/json' --data @- "$seerrBase/api/v1/settings/$kind" >/dev/null
      else
        printf '%s' "$body" | $curl -fsS -b "$cookieJar" -X PUT -H 'Content-Type: application/json' --data @- "$seerrBase/api/v1/settings/$kind/$id" >/dev/null
      fi
    }

    run_flow() (
      set -euo pipefail

      # ---- discover Sonarr/Radarr settings ---------------------------
      sonarrKey=$(read_api_key ${config.services.sonarr.dataDir}/config.xml)
      radarrKey=$(read_api_key ${config.services.radarr.dataDir}/config.xml)

      $curl -fsS -H "X-Api-Key: $sonarrKey" "$sonarrBase/api/v3/system/status" >/dev/null
      $curl -fsS -H "X-Api-Key: $radarrKey" "$radarrBase/api/v3/system/status" >/dev/null

      ensure_root_folder "$sonarrBase" "$sonarrKey" "${mediaRoot}/tv"
      ensure_root_folder "$radarrBase" "$radarrKey" "${mediaRoot}/movies"

      IFS=$'\t' read -r sonarrProfileId sonarrProfileName < <(pick_profile "$sonarrBase" "$sonarrKey") || true
      IFS=$'\t' read -r radarrProfileId radarrProfileName < <(pick_profile "$radarrBase" "$radarrKey") || true
      if [ -z "$sonarrProfileId" ] || [ -z "$radarrProfileId" ]; then
        echo "media-seerr-init: no quality profile found on Sonarr/Radarr" >&2
        return 1
      fi

      # ---- sign in to Seerr (creates the admin on a fresh install) ----
      cookieJar=$($mktemp)
      trap '$rm -f "$cookieJar"' EXIT

      initialized=$($curl -fsS "$seerrBase/api/v1/settings/public" | $jq -r '.initialized // false')
      # On a fresh install the Jellyfin connection has to be supplied with
      # the login (MediaServerType.NOT_CONFIGURED == 4); once configured,
      # sending a hostname again is rejected with "Jellyfin hostname already
      # configured", so only the credentials are sent then. This makes the
      # login safe to retry after a partially finished run.
      mediaServerType=$($curl -fsS "$seerrBase/api/v1/settings/public" | $jq -r '.mediaServerType // 4')
      loginBody=$($jq -n \
        --arg u "${jellyfinAdminUser}" \
        --arg p "${jellyfinAdminPassword}" \
        '{username:$u,password:$p,email:$u}')
      if [ "$mediaServerType" = "4" ]; then
        loginBody=$(printf '%s' "$loginBody" | $jq \
          --arg h 127.0.0.1 \
          --argjson port 8096 \
          --argjson serverType 2 \
          '. + {hostname:$h, port:$port, useSsl:false, urlBase:"", serverType:$serverType}')
      fi
      # log in and keep the session cookie; capture the HTTP status so a
      # failure is retried (and logged) instead of silently continuing
      loginResult=$(printf '%s' "$loginBody" \
        | $curl -sS -w '\n%{http_code}' -c "$cookieJar" -X POST -H 'Content-Type: application/json' --data @- "$seerrBase/api/v1/auth/jellyfin")
      loginCode=$(printf '%s' "$loginResult" | $tail -n1)
      loginResponse=$(printf '%s' "$loginResult" | $sed '$d')
      if [ "$loginCode" != "200" ]; then
        echo "media-seerr-init: Seerr Jellyfin login returned HTTP $loginCode: $loginResponse" >&2
        [ -f ${config.services.seerr.configDir}/logs/seerr.log ] && $tail -n 30 ${config.services.seerr.configDir}/logs/seerr.log >&2
        return 1
      fi
      if [ "$initialized" != "true" ]; then
        $curl -fsS -b "$cookieJar" -X POST "$seerrBase/api/v1/settings/initialize" >/dev/null
      fi

      # ---- register Sonarr + Radarr ----------------------------------
      sonarrBody=$($jq -n \
        --arg apiKey "$sonarrKey" \
        --argjson activeProfileId "$sonarrProfileId" \
        --arg activeProfileName "$sonarrProfileName" \
        --arg activeDirectory "${mediaRoot}/tv" \
        '{
          name: "Sonarr",
          hostname: "127.0.0.1",
          port: 8989,
          apiKey: $apiKey,
          useSsl: false,
          baseUrl: "",
          activeProfileId: $activeProfileId,
          activeProfileName: $activeProfileName,
          activeDirectory: $activeDirectory,
          is4k: false,
          enableSeasonFolders: true,
          isDefault: true,
          externalUrl: "",
          syncEnabled: true,
          preventSearch: false,
          tagRequests: false,
          overrideRule: [],
          tags: [],
          animeTags: [],
          seriesType: "standard",
          monitorNewItems: "all"
        }')

      radarrBody=$($jq -n \
        --arg apiKey "$radarrKey" \
        --argjson activeProfileId "$radarrProfileId" \
        --arg activeProfileName "$radarrProfileName" \
        --arg activeDirectory "${mediaRoot}/movies" \
        '{
          name: "Radarr",
          hostname: "127.0.0.1",
          port: 7878,
          apiKey: $apiKey,
          useSsl: false,
          baseUrl: "",
          activeProfileId: $activeProfileId,
          activeProfileName: $activeProfileName,
          activeDirectory: $activeDirectory,
          is4k: false,
          isDefault: true,
          minimumAvailability: "released",
          externalUrl: "",
          syncEnabled: true,
          preventSearch: false,
          tagRequests: false,
          overrideRule: [],
          tags: []
        }')

      configure_dvr sonarr "$sonarrBody"
      configure_dvr radarr "$radarrBody"

      # scan the existing libraries right away so already-present media is
      # immediately marked available in the Seerr UI
      $curl -fsS -b "$cookieJar" -X POST "$seerrBase/api/v1/settings/jobs/sonarr-scan" >/dev/null || true
      $curl -fsS -b "$cookieJar" -X POST "$seerrBase/api/v1/settings/jobs/radarr-scan" >/dev/null || true
    )

    # retry until a deadline: on a fresh boot the *arrs and Seerr may still be
    # creating their databases; every step above is guarded/idempotent
    deadline=$(( $($date +%s) + 900 ))
    while true; do
      # NOTE: run_flow is deliberately *not* called from an `if`/`&&`/`||`
      # condition: bash disables errexit for functions invoked that way, so
      # a failing step in the middle of run_flow would be masked and the
      # marker written even though Seerr was never configured. Calling it as
      # a plain command keeps `set -e` effective inside the subshell.
      run_flow
      rc=$?
      if [ "$rc" -eq 0 ]; then
        $touch "$marker"
        exit 0
      fi
      if [ "$( $date +%s )" -ge "$deadline" ]; then
        echo "media-seerr-init: giving up after 15 minutes" >&2
        exit 1
      fi
      $sleep 5
    done
  '';

  # Declarative *arr/Prowlarr wiring, closing the gap left by seerrInit.
  #
  # seerrInit only registers Sonarr and Radarr *in Seerr*; it never gives the
  # *arrs a download client or an indexer. Without those an approved request is
  # added to Radarr/Sonarr (and shows up in Seerr as "requested") but nothing
  # ever searches: Radarr logs "Searching indexers for [...]. 0 active
  # indexers", grabs nothing and therefore never hands a torrent to
  # qBittorrent or imports anything into Jellyfin. This unit wires the chain
  # up on first boot:
  #   1. adds qBittorrent as the download client of Sonarr and Radarr,
  #   2. registers Sonarr and Radarr as Prowlarr applications, and
  #   3. adds the public indexers from `prowlarrIndexers` to Prowlarr,
  # after which Prowlarr pushes a Torznab indexer to both *arrs.
  #
  # Like the other bootstrap units it is idempotent (each step inspects the
  # current configuration first), guarded by a marker file and retried until a
  # deadline, because on a fresh boot the services are still starting (and
  # Prowlarr may still be fetching its indexer definitions).
  mediaArrInit = pkgs.writeShellScript "media-arr-init" ''
    set -uo pipefail

    sonarrBase=http://127.0.0.1:8989
    radarrBase=http://127.0.0.1:7878
    prowlarrBase=http://127.0.0.1:9696
    marker=${config.services.sonarr.dataDir}/.nixos-media-arr-configured

    curl=${lib.getExe pkgs.curl}
    jq=${lib.getExe pkgs.jq}
    sleep=${lib.getExe' pkgs.coreutils "sleep"}
    touch=${lib.getExe' pkgs.coreutils "touch"}
    seq=${lib.getExe' pkgs.coreutils "seq"}
    date=${lib.getExe' pkgs.coreutils "date"}
    sed=${lib.getExe pkgs.gnused}
    head=${lib.getExe' pkgs.coreutils "head"}

    [ -f "$marker" ] && exit 0

    # wait for a config.xml to appear and print the *arr API key it contains
    read_api_key() {
      local file=$1 key
      for _ in $($seq 1 300); do
        if [ -f "$file" ]; then
          key=$($sed -n 's:.*<ApiKey>\([^<]*\)</ApiKey>.*:\1:p' "$file" | $head -n1)
          if [ -n "$key" ]; then
            printf '%s' "$key"
            return 0
          fi
        fi
        $sleep 2
      done
      return 1
    }

    # create or update the qBittorrent download client on one *arr
    ensure_download_client() {
      local base=$1 key=$2 categoryField=$3 category=$4
      local schema body existing id
      schema=$($curl -fsS -H "X-Api-Key: $key" "$base/api/v3/downloadclient/schema")
      body=$(printf '%s' "$schema" | $jq \
        --arg host 127.0.0.1 \
        --argjson port ${toString config.services.qbittorrent.webuiPort} \
        --arg user "${qbittorrentUser}" \
        --arg pass "${qbittorrentPassword}" \
        --arg catfield "$categoryField" \
        --arg cat "$category" \
        '[.[] | select(.implementation == "QBittorrent")][0]
         | .enable = true
         | .name = "qBittorrent"
         | .fields = (.fields | map(
             if .name == "host" then .value = $host
             elif .name == "port" then .value = $port
             elif .name == "useSsl" then .value = false
             elif .name == "username" then .value = $user
             elif .name == "password" then .value = $pass
             elif .name == $catfield then .value = $cat
             else . end))')
      existing=$($curl -fsS -H "X-Api-Key: $key" "$base/api/v3/downloadclient")
      id=$(printf '%s' "$existing" | $jq -r '([.[] | select(.name == "qBittorrent")][0].id) // empty')
      if [ -n "$id" ]; then
        printf '%s' "$body" | $jq --argjson id "$id" '.id = $id' \
          | $curl -fsS -X PUT -H "X-Api-Key: $key" -H 'Content-Type: application/json' --data @- "$base/api/v3/downloadclient/$id" >/dev/null
      else
        printf '%s' "$body" \
          | $curl -fsS -X POST -H "X-Api-Key: $key" -H 'Content-Type: application/json' --data @- "$base/api/v3/downloadclient" >/dev/null
      fi
    }

    # register one Prowlarr application (Sonarr/Radarr) if missing
    ensure_application() {
      local impl=$1 key=$2 port=$3
      local schema body existing id
      schema=$($curl -fsS -H "X-Api-Key: $prowlarrKey" "$prowlarrBase/api/v1/applications/schema")
      body=$(printf '%s' "$schema" | $jq \
        --arg impl "$impl" \
        --arg url "http://127.0.0.1:$port" \
        --arg key "$key" \
        '[.[] | select(.implementation == $impl)][0]
         | .enable = true
         | .name = $impl
         | .fields = (.fields | map(
             if .name == "prowlarrUrl" then .value = "http://127.0.0.1:9696"
             elif .name == "baseUrl" then .value = $url
             elif .name == "apiKey" then .value = $key
             else . end))')
      existing=$($curl -fsS -H "X-Api-Key: $prowlarrKey" "$prowlarrBase/api/v1/applications")
      id=$(printf '%s' "$existing" | $jq -r --arg n "$impl" '([.[] | select(.name == $n)][0].id) // empty')
      if [ -n "$id" ]; then
        printf '%s' "$body" | $jq --argjson id "$id" '.id = $id' \
          | $curl -fsS -X PUT -H "X-Api-Key: $prowlarrKey" -H 'Content-Type: application/json' --data @- "$prowlarrBase/api/v1/applications/$id" >/dev/null
      else
        printf '%s' "$body" \
          | $curl -fsS -X POST -H "X-Api-Key: $prowlarrKey" -H 'Content-Type: application/json' --data @- "$prowlarrBase/api/v1/applications" >/dev/null
      fi
    }

    # add a public indexer (by Prowlarr definition name) if missing. Prowlarr
    # ships/updates its Cardigann definitions from indexers.prowlarr.com, so
    # on a host that cannot reach it yet the definition may be missing; that
    # is logged and skipped rather than failing the whole unit (the download
    # client and application wiring above is what makes requests reach
    # qBittorrent, and the indexer is retried on a later run/rebuild).
    ensure_indexer() {
      local definition=$1
      local schema body profileId
      if $curl -fsS -H "X-Api-Key: $prowlarrKey" "$prowlarrBase/api/v1/indexer" \
        | $jq -e --arg d "$definition" 'any(.[]; .definitionName == $d)' >/dev/null; then
        return 0
      fi
      schema=$($curl -fsS -H "X-Api-Key: $prowlarrKey" "$prowlarrBase/api/v1/indexer/schema")
      if ! printf '%s' "$schema" | $jq -e --arg d "$definition" 'any(.[]; .definitionName == $d)' >/dev/null; then
        echo "media-arr-init: no Prowlarr indexer definition named '$definition'" >&2
        echo "media-arr-init: (indexer definitions not downloaded yet?); skipping" >&2
        return 0
      fi
      profileId=$($curl -fsS -H "X-Api-Key: $prowlarrKey" "$prowlarrBase/api/v1/appprofile" | $jq -r '.[0].id')
      body=$(printf '%s' "$schema" | $jq \
        --arg d "$definition" \
        --argjson profileId "$profileId" \
        '([.[] | select(.definitionName == $d)][0])
         | {
             enable: true,
             name: .name,
             implementation: .implementation,
             implementationName: .implementationName,
             configContract: .configContract,
             definitionName: .definitionName,
             protocol: .protocol,
             priority: .priority,
             appProfileId: $profileId,
             tags: [],
             fields: [
               { name: "definitionFile", value: .definitionName },
               { name: "baseUrl", value: .indexerUrls[0] },
               { name: "torrentBaseSettings.preferMagnetUrl", value: true }
             ]
           }')
      printf '%s' "$body" \
        | $curl -fsS -X POST -H "X-Api-Key: $prowlarrKey" -H 'Content-Type: application/json' --data @- "$prowlarrBase/api/v1/indexer" >/dev/null
    }

    run_flow() (
      set -euo pipefail

      sonarrKey=$(read_api_key ${config.services.sonarr.dataDir}/config.xml)
      radarrKey=$(read_api_key ${config.services.radarr.dataDir}/config.xml)
      prowlarrKey=$(read_api_key ${config.services.prowlarr.dataDir}/config.xml)

      # every service must be answering before it is touched
      $curl -fsS -H "X-Api-Key: $sonarrKey" "$sonarrBase/api/v3/system/status" >/dev/null
      $curl -fsS -H "X-Api-Key: $radarrKey" "$radarrBase/api/v3/system/status" >/dev/null
      $curl -fsS -H "X-Api-Key: $prowlarrKey" "$prowlarrBase/api/v1/system/status" >/dev/null
      $curl -fsS -o /dev/null "http://127.0.0.1:${toString config.services.qbittorrent.webuiPort}/"

      # qBittorrent is the download client; the category keeps Radarr/Sonarr
      # downloads separate (qBittorrent creates it on first use)
      ensure_download_client "$sonarrBase" "$sonarrKey" tvCategory sonarr
      ensure_download_client "$radarrBase" "$radarrKey" movieCategory radarr

      # Prowlarr pushes its indexers to these applications
      ensure_application Sonarr "$sonarrKey" 8989
      ensure_application Radarr "$radarrKey" 7878

      for definition in ${lib.escapeShellArgs prowlarrIndexers}; do
        ensure_indexer "$definition"
      done

      # sync the indexers to Sonarr/Radarr right away instead of waiting for
      # Prowlarr's periodic sync
      $curl -fsS -X POST -H "X-Api-Key: $prowlarrKey" -H 'Content-Type: application/json' \
        -d '{"name":"ApplicationIndexerSync"}' "$prowlarrBase/api/v1/command" >/dev/null
    )

    # retry until a deadline: on a fresh boot the *arrs and Prowlarr may still
    # be creating their databases (and Prowlarr may still be fetching indexer
    # definitions); every step above is guarded/idempotent
    deadline=$(( $($date +%s) + 900 ))
    while true; do
      run_flow
      rc=$?
      if [ "$rc" -eq 0 ]; then
        $touch "$marker"
        exit 0
      fi
      if [ "$( $date +%s )" -ge "$deadline" ]; then
        echo "media-arr-init: giving up after 15 minutes" >&2
        exit 1
      fi
      $sleep 5
    done
  '';
  # Heal Jellyfin's series -> seasons -> episodes tree.
  #
  # Jellyfin can end up with series whose child queries come back empty even
  # though the Season/Episode items exist with correct ParentId/SeriesId
  # links: on wranHearst *every* series answered /Shows/{id}/Seasons and
  # /Shows/{id}/Episodes with {"Items":[],"TotalRecordCount":0} (the Series
  # item even reported ChildCount=0 while RecursiveItemCount=30), so the web
  # client's episode queueing found nothing to play and every series failed
  # with "Playback error, unable to find valid media source to play" (movies
  # kept working, since they need no tree). A plain library scan does NOT
  # repair this - only a recursive refresh of the series item re-validates
  # the child links and heals it (verified: after
  # POST /Items/{id}/Refresh?Recursive=true the seasons/episodes queries
  # return again, playback works, and a subsequent /Library/Refresh scan
  # keeps the tree intact).
  #
  # This unit therefore runs on every boot after media-jellyfin-init and
  # refreshes any series whose episode query is empty. It is a no-op while
  # the tree is healthy (one cheap request per series).
  jellyfinTreeHeal = pkgs.writeShellScript "media-jellyfin-tree-heal" ''
    set -uo pipefail

    base=http://127.0.0.1:8096
    curl=${lib.getExe pkgs.curl}
    jq=${lib.getExe pkgs.jq}
    sleep=${lib.getExe' pkgs.coreutils "sleep"}
    date=${lib.getExe' pkgs.coreutils "date"}
    authHeader='Authorization: MediaBrowser Client="nixos-media", Device="nixos-media", DeviceId="nixos-media", Version="1.0"'

    run_flow() (
      set -euo pipefail

      # the accounts are created by media-jellyfin-init (which this unit
      # orders itself after), so authentication should succeed immediately.
      # Authenticate exactly ONCE and take token and user id from the same
      # response: Jellyfin invalidates the previous token when the same
      # device authenticates again, so a second login would break the first
      # token mid-run.
      auth=$($curl -fsS -X POST "$base/Users/AuthenticateByName" \
        -H "$authHeader" -H 'Content-Type: application/json' \
        -d '{"Username":"${jellyfinAdminUser}","Pw":"${jellyfinAdminPassword}"}')
      token=$(printf '%s' "$auth" | $jq -r '.AccessToken // empty')
      userId=$(printf '%s' "$auth" | $jq -r '.User.Id // empty')
      if [ -z "$token" ] || [ -z "$userId" ]; then
        echo "media-jellyfin-tree-heal: could not authenticate" >&2
        return 1
      fi
      apiHeader="Authorization: MediaBrowser Token=\"$token\""

      healed=0
      # list the series in one captured request: set -e does not abort on
      # failures inside a for-word command substitution, so results must be
      # checked explicitly (see the note on the seerrInit retry loop above)
      seriesList=$($curl -fsS -H "$apiHeader" \
          "$base/Items?IncludeItemTypes=Series&Recursive=true&Limit=200")
      # the same query the web client performs while queueing a series
      # playback; empty result => the tree is broken => heal it
      for id in $(printf '%s' "$seriesList" | $jq -r '.Items[].Id'); do
        resp=$($curl -fsS -H "$apiHeader" \
          "$base/Shows/$id/Episodes?UserId=$userId&limit=1")
        count=$(printf '%s' "$resp" | $jq -r '.TotalRecordCount // 0')
        if [ "$count" = "0" ]; then
          echo "media-jellyfin-tree-heal: series $id reports 0 episodes, healing"
          $curl -fsS -X POST -H "$apiHeader" \
            "$base/Items/$id/Refresh?Recursive=true&MetadataRefreshMode=ValidationOnly&ImageRefreshMode=None" \
            >/dev/null
          healed=$((healed + 1))
        fi
      done
      echo "media-jellyfin-tree-heal: checked series, healed $healed"
    )

    # retry until a deadline (Jellyfin may still be initializing on boot)
    deadline=$(( $($date +%s) + 600 ))
    while true; do
      if run_flow; then
        exit 0
      fi
      if [ "$( $date +%s )" -ge "$deadline" ]; then
        echo "media-jellyfin-tree-heal: giving up after 10 minutes" >&2
        exit 1
      fi
      $sleep 5
    done
  '';
in
{
  users.groups.${mediaGroup} = { };

  # ---------------------------------------------------------------------
  # qBittorrent (qbittorrent-nix): headless torrent client
  # ---------------------------------------------------------------------
  services.qbittorrent = {
    enable = true;
    group = mediaGroup;
    # 8080 is taken by k3s's traefik ingress ("Unable to bind ... address is
    # already in use" in the journal); use a port nothing else claims
    webuiPort = 8085;
    # accept the legal notice and keep everything under /srv/media
    serverConfig = {
      LegalNotice.Accepted = true;
      Session = {
        # default torrent save location
        SavePath = "${mediaRoot}/downloads";
        # don't touch files that are being seeded from the completed dir
        TorrentContentLayout = "Original";
      };
      Preferences.Downloads.SavePath = "${mediaRoot}/downloads";
      # WebUI login: wranHearst / whmedia (matches the Jellyfin admin)
      # Password_PBKDF2 = pbkdf2-hmac-sha512("whmedia", salt "zeusolympia-qbittorrent-webui", 100000 iters, 64 bytes)
      # qBittorrent stores the secret as base64(salt) + ":" + base64(hash); QSettings wraps
      # that QByteArray as @ByteArray(...), i.e. @ByteArray(base64(salt):base64(hash)).
      # (regenerate with https://codeberg.org/feathecutie/qbittorrent_password or any hashlib.pbkdf2_hmac call)
      Preferences.WebUI.Username = "wranHearst";
      Preferences.WebUI.Password_PBKDF2 =
        "@ByteArray(emV1c29seW1waWEtcWJpdHRvcnJlbnQtd2VidWk=:GuDeJ35kVKubzYliy1Z15BR/rUXn926Wm6daTevxTNqu/ONwXOTgrQMARtjGWgC7Wsm8lnCB9frlWXsPZRpq0g==)";
    };
  };
  # make qBittorrent's downloaded files group-writable so Sonarr/Radarr can
  # move (not just read) them during import
  systemd.services.qbittorrent.serviceConfig.UMask = "0002";

  # ---------------------------------------------------------------------
  # Prowlarr: indexer manager; pushes indexers to Sonarr/Radarr
  # ---------------------------------------------------------------------
  services.prowlarr.enable = true;
  # the prowlarr module uses a DynamicUser; its StateDirectory setup cannot
  # work through an impermanence bind mount (systemd's move-mount dance for
  # dynamic users fails with "Device or resource busy"), so give it a
  # static user instead — with a static user systemd just chowns the (already
  # bind-mounted, hence persisted) state directory, like for sonarr/radarr
  users.users.prowlarr = {
    isSystemUser = true;
    group = "prowlarr";
  };
  users.groups.prowlarr = { };
  systemd.services.prowlarr.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = "prowlarr";
    Group = "prowlarr";
    StateDirectory = lib.mkForce "prowlarr";
  };

  # ---------------------------------------------------------------------
  # Sonarr / Radarr: TV series + movie library managers
  # ---------------------------------------------------------------------
  services.sonarr = {
    enable = true;
    group = mediaGroup;
  };
  # imported files stay group-writable for the rest of the media group
  systemd.services.sonarr.serviceConfig.UMask = lib.mkForce "0002";
  services.radarr = {
    enable = true;
    group = mediaGroup;
  };
  systemd.services.radarr.serviceConfig.UMask = lib.mkForce "0002";

  # ---------------------------------------------------------------------
  # Jellyfin: media server
  # ---------------------------------------------------------------------
  services.jellyfin = {
    enable = true;
    group = mediaGroup;
  };
  # Jellyfin only needs to read the media library
  users.users.jellyfin.extraGroups = [ mediaGroup ];

  # declarative Jellyfin accounts: completes the first-boot setup wizard and
  # creates the admin user `wranHearst` (password `whmedia`) and the regular
  # (non-admin) viewer `sieyes` (password `sieyesmedia`), then registers the
  # TV/movie library folders. The media library lives on a persisted
  # directory (see below), so the Jellyfin database is written there too and
  # everything survives reboots.
  #
  # Runs as a separate oneshot *after* jellyfin.service (Jellyfin's unit has
  # TimeoutSec=15, too short for polling a server that may take a while to
  # listen). A marker file in the (persisted) config dir makes it a no-op
  # after the first successful run; if a pre-existing install rejects the
  # declarative admin password the unit just logs and exits 0 instead of
  # breaking Jellyfin on every boot.
  systemd.services.jellyfin.wants = [
    "media-jellyfin-init.service"
    "media-jellyfin-tree-heal.service"
  ];
  systemd.services.media-jellyfin-init = {
    description = "declaratively set up Jellyfin users and libraries";
    after = [ "jellyfin.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = config.services.jellyfin.user;
      Group = config.services.jellyfin.group;
      RemainAfterExit = true;
    };
    # the writeShellScript-generated script is referenced as a store path
    serviceConfig.ExecStart = "${jellyfinInit}";
  };

  # ---------------------------------------------------------------------
  # series tree healing (see the jellyfinTreeHeal comment above)
  # ---------------------------------------------------------------------
  systemd.services.media-jellyfin-tree-heal = {
    description = "heal Jellyfin series whose seasons/episodes queries are empty";
    after = [
      "jellyfin.service"
      "media-jellyfin-init.service"
    ];
    wants = [ "media-jellyfin-init.service" ];
    serviceConfig = {
      Type = "oneshot";
      # stay "active (exited)" after a successful run so the unit visibly
      # reflects the (healthy) tree state instead of dropping to inactive
      RemainAfterExit = true;
      User = config.services.jellyfin.user;
      Group = config.services.jellyfin.group;
      ExecStart = "${jellyfinTreeHeal}";
    };
  };

  # ---------------------------------------------------------------------
  # ytdl-sub: download YouTube channels into the TV library
  # ---------------------------------------------------------------------
  # Runs every 6 hours and drops each subscribed channel into
  # ${mediaRoot}/tv/<Channel Name>/Season <year>/... using ytdl-sub's
  # "Jellyfin TV Show by Date" preset (episodes numbered by upload date,
  # with tvshow.nfo / episode .nfo files, poster.jpg and fanart.jpg), so
  # Jellyfin picks them up as regular TV shows in the existing Series
  # library — no extra library configuration needed.
  #
  # To add a channel, add an entry under subscriptions below and rebuild:
  #   subscriptions.youtube_channels_as_tv_shows."Channel Name" =
  #     "https://www.youtube.com/@ExampleChannel";
  services.ytdl-sub.group = mediaGroup; # primary group "media": everything
  # ytdl-sub writes into the TV library is automatically owned by the
  # media group, like the rest of the stack
  services.ytdl-sub.instances.youtube_tv = {
    enable = true;
    schedule = "0/6:0"; # every 6 hours
    # ytdl-sub writes straight into the Sonarr-managed TV library; the
    # service itself is heavily sandboxed (ProtectSystem=strict), so the
    # output directory must be whitelisted explicitly.
    readWritePaths = [ "${mediaRoot}/tv" ];
    # extend the prebuilt preset (redefining it by name is rejected by
    # ytdl-sub) and point its output at the TV library
    config.presets.youtube_channels_as_tv_shows = {
      preset = [ "Jellyfin TV Show by Date" ];
      overrides.tv_show_directory = "${mediaRoot}/tv";
    };
    subscriptions.youtube_channels_as_tv_shows = {
      # "Channel Name" = "https://www.youtube.com/@ExampleChannel";
    };
  };
  # keep downloaded files group-writable like the rest of the stack
  systemd.services."ytdl-sub-youtube_tv".serviceConfig.UMask = "0002";

  # ---------------------------------------------------------------------
  # Seerr (services.jellyseerr is the renamed-option alias of
  # services.seerr): request management UI in front of Sonarr/Radarr
  # ---------------------------------------------------------------------
  services.seerr.enable = true;
  # same reason as prowlarr above: the seerr module's DynamicUser cannot
  # survive the impermanence bind mount of its state directory, so run it
  # as a static user instead
  users.users.seerr = {
    isSystemUser = true;
    group = "seerr";
  };
  users.groups.seerr = { };
  systemd.services.seerr.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = "seerr";
    Group = "seerr";
    StateDirectory = lib.mkForce "seerr";
  };

  # Declarative Radarr/Sonarr integration (see seerrInit above). Runs after
  # the Jellyfin accounts/libraries exist, because the first Seerr login
  # authenticates against Jellyfin. media-jellyfin-init is a oneshot, so
  # ordering also waits for it to finish.
  systemd.services.seerr.wants = [ "media-seerr-init.service" ];
  systemd.services.media-seerr-init = {
    description = "declaratively configure Seerr (Jellyfin login, Radarr/Sonarr)";
    after = [
      "seerr.service"
      "media-jellyfin-init.service"
    ];
    wants = [ "media-jellyfin-init.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${seerrInit}";
    };
  };

  # Declarative download-client/indexer wiring (see mediaArrInit above). This
  # is what makes an approved Seerr request actually reach qBittorrent: it
  # gives Sonarr/Radarr a qBittorrent download client and a Prowlarr-backed
  # indexer. Runs on every boot (the marker file makes it a no-op after the
  # first successful run) but only after the stack's services are up.
  systemd.services.media-arr-init = {
    description = "declaratively wire qBittorrent and Prowlarr into Sonarr/Radarr";
    wantedBy = [ "multi-user.target" ];
    after = [
      "sonarr.service"
      "radarr.service"
      "prowlarr.service"
      "qbittorrent.service"
    ];
    wants = [
      "sonarr.service"
      "radarr.service"
      "prowlarr.service"
      "qbittorrent.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${mediaArrInit}";
    };
  };

  # (see the impermanence block below for why this tmpfiles block is kept
  # alongside it)
  systemd.tmpfiles.settings."10-media-root" = {
    "${mediaRoot}"."d" = {
      mode = "0775";
      user = "root";
      group = mediaGroup;
    };
    "${mediaRoot}/downloads"."d" = {
      mode = "0775";
      user = "qbittorrent";
      group = mediaGroup;
    };
    "${mediaRoot}/tv"."d" = {
      mode = "0775";
      user = "sonarr";
      group = mediaGroup;
    };
    "${mediaRoot}/movies"."d" = {
      mode = "0775";
      user = "radarr";
      group = mediaGroup;
    };
  };

  # ---------------------------------------------------------------------
  # impermanence: wranHearst wipes its root on every reboot (see
  # ../fs/impermanence.nix), so all state of this stack must be persisted
  # explicitly under /persist:
  #   - the media library itself (/srv/media, incl. downloads/tv/movies)
  #   - the per-service state directories (databases, configs, API keys,
  #     torrent state, ytdl-sub subscription state)
  #
  # The previous systemd.tmpfiles block that created ${mediaRoot} (and the
  # downloads/tv/movies subdirectories) on every boot was evaluated against
  # the impermanence declarations below, and the result is: mostly
  # redundant, but not entirely — so it is kept (with a trimmed role).
  #
  # Impermanence creates every persisted backing directory on a fresh boot
  # with the user/group/mode declared on its entry — but only *at creation
  # time* (create-directories.bash skips existing directories), and
  # directories that are parents of other persisted entries are created
  # first, in a "parent" pass with *default* permissions (root:root 0755).
  # ${mediaRoot} is exactly such a parent (of the
  # downloads/tv/movies entries below), so its declared root:media 0775 is
  # never applied on a fresh boot — the tmpfiles block below re-asserts
  # ownership/mode on every boot (it runs after the bind mounts, i.e. on
  # the persisted tree, so the fix itself persists). For the
  # subdirectories tmpfiles is pure redundancy (impermanence creates them
  # with the right ownership), but re-asserting is idempotent and cheap,
  # and keeps the ownership documented in exactly one shape.
  #
  # NOTE: the service users referenced below (qbittorrent, sonarr, radarr)
  # are declared by this module, and impermanence's directory-creation
  # activation runs after users/groups, so they always exist by then.
  # ---------------------------------------------------------------------
  environment.persistence."/persist".directories =
    let
      # persisted directory with explicit ownership/mode
      d = directory: user: group: mode: { inherit directory user group mode; };
    in
    [
      # media library
      (d mediaRoot "root" mediaGroup "0775")
      (d "${mediaRoot}/downloads" "qbittorrent" mediaGroup "0775")
      (d "${mediaRoot}/tv" "sonarr" mediaGroup "0775")
      (d "${mediaRoot}/movies" "radarr" mediaGroup "0775")

      # qBittorrent: profile/config dir (default --profile directory)
      "/var/lib/qBittorrent"
      # Sonarr / Radarr: dataDir defaults (/var/lib/<name>/.config/... for
      # sonarr/radarr, managed via StateDirectory=<name>)
      "/var/lib/sonarr"
      "/var/lib/radarr"
      # Prowlarr: state dir (module runs as a static user now, see above,
      # so systemd chowns the bind-mounted StateDirectory normally)
      "/var/lib/prowlarr"
      # Jellyfin: dataDir (configDir = dataDir/config) + cache + logs
      "/var/lib/jellyfin"
      "/var/cache/jellyfin"
      "/var/log/jellyfin"
      # Seerr (services.jellyseerr alias): state dir; the module runs as a
      # static user now (see above) and its configDir defaults to
      # /var/lib/seerr for stateVersion >= 26.05 (26.11 on wranHearst), so
      # that single directory is all of its state
      "/var/lib/seerr"
      # ytdl-sub instances: StateDirectory=ytdl-sub/<instance> (download
      # state, subscription caches); the instance unit is
      # ytdl-sub-youtube_tv
      "/var/lib/ytdl-sub"
    ];
}