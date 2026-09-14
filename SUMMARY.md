# Summary — harmonia binary cache for the linux 6.18 kernel used by the `vm` scripts

Goal: give the hosts `lanchamarcou` and `augtibcalcla` a binary cache (hosted on
`wranHearst`) from which they can fetch the linux 6.18 kernel binary required to
build the `headless` dev shell of the `frontArmToPlane` input (whose `pi-vm`
`vm` scripts build NixOS VMs with frontArmToPlane's own nixpkgs, kernel
6.18.50).

## Steps

1. **Explored the repo**
   - `flake.nix` wires host configs from `empTriageCan/<host>.nix` (module
     lists rooted at `zeusOlympia`) via `heidRunOverCar/mkNixOS.nix` /
     `mkColmenaHive.nix`; per-host dirs (`zeusOlympia/<host>`) auto-import
     every `.nix` file they contain (`localLib.mkDirectoryImporterModule`).
   - Inspected the `frontArmToPlane` input: its `localPkgsArgs.pkgs` defaults
     to `linuxPackages_6_18` (6.18.50), and its `headless` shell contains
     `pi-vm.run-pi-vm` / `run-pi-microvm` — the `vm` scripts whose VMs need
     that exact kernel.

2. **Added the harmonia module** (`zeusOlympia/harmonia/default.nix`)
   - `services.harmonia` (harmonia 3.2.0 from nixpkgs) serving on
     `[::]:5000`, reachable from the LAN (`networking.firewall`).
   - Signs with the key in `./cache-key.sec`; the matching public key is in
     `./cache-key.pub`.
   - Keys generated with `nix-store --generate-binary-cache-key wranHearst-cache ...`
     (public key: `wranHearst-cache:G6wjtR3BPM+c3EZGSI1i4b/j5YM/SvKEMp4bUUyqNEA=`).
     Note: the secret key lives in the nix store (world-readable) — should move
     to sops if the cache ever leaves the private LAN.
   - Advertises the cache over mDNS via `services.avahi.extraServiceFiles`
     (same pattern as the forgejo module).

3. **Imported the module into `wranHearst` and provided the kernel**
   - Added `"./harmonia"` to the wranHearst module list in
     `empTriageCan/wranHearst.nix`.
   - Added `zeusOlympia/wranHearst/linuxKernel.nix` (auto-imported by
     `wranHearst/default.nix`) which sets
     `boot.kernelPackages = frontArmToPlane.localPkgsArgs.pkgs.linuxPackages_6_18;`
     — wranHearst boots the exact linux 6.18.50 kernel used by the `vm`
     scripts, so its closure is present in wranHearst's store and harmonia
     (which serves paths straight from the local nix database) can serve it.

4. **Gave the client hosts access to the cache**
   - `zeusOlympia/lanchamarcou/binaryCache.nix` and
     `zeusOlympia/augtibcalcla/binaryCache.nix`: add
     `http://wranHearst.local:5000` to `nix.settings.substituters` and the
     cache public key (read from `../harmonia/cache-key.pub`) to
     `nix.settings.trusted-public-keys`, so both hosts can substitute the
     kernel (and other paths) when building the `headless` shell of
     `frontArmToPlane`.

5. **Testing**
   - `nix eval`: harmonia enabled, `boot.kernelPackages.kernel.version` =
     `6.18.50`, firewall allows 5000; both clients got the new substituter
     and the `wranHearst-cache` trusted key; the colmena hive still evaluates.
   - Built `nixosConfigurations.wranHearst.config.system.build.toplevel`
     successfully (realizes the 6.18.50 kernel closure:
     `/nix/store/8j2c3cwd0fkmry81hgir8n2bm852a01j-linux-6.18.50`, byte-identical
     to the kernel frontArmToPlane's VMs use).
   - Inspected the generated `harmonia.service` / `harmonia.socket` units:
     sign key credential wired, `[::]:5000` listen stream.
   - Live smoke test: ran the exact `harmonia-cache` binary with the exact
     generated `harmonia.toml` + sign key (on port 5090 here, since port 5000
     was already taken by an unrelated service on the dev machine):
     - `narinfo` for the kernel is served and signed with `wranHearst-cache`.
     - `nix copy --from http://localhost:5090 --store /tmp/fresh-store`
       successfully substituted the kernel into a fresh store (signature
       verified against the cache public key).
     - Built frontArmToPlane's `packages.x86_64-linux.pi-vm.run-pi-vm` (the
       2.7 GiB VM-runner closure containing the VM and the 6.18 kernel) into a
       fresh store using **only** the harmonia cache as substituter — all
       paths substituted successfully.
   - Built frontArmToPlane's `devShells.x86_64-linux.headless` (14.4 GiB
     closure) successfully, confirming the `headless` shell is buildable.

## Resulting files

- `zeusOlympia/harmonia/default.nix` (new harmonia service module)
- `zeusOlympia/harmonia/cache-key.sec` / `cache-key.pub` (cache signing keys)
- `zeusOlympia/wranHearst/linuxKernel.nix` (boots frontArmToPlane's linux 6.18)
- `zeusOlympia/lanchamarcou/binaryCache.nix` (client cache config)
- `zeusOlympia/augtibcalcla/binaryCache.nix` (client cache config)
- `empTriageCan/wranHearst.nix` (imports `./harmonia`)