# Summary: garage secrets via sops-nix

Goal: make `./zeusOlympia/garage/` read its secrets (`GARAGE_RPC_SECRET`,
`GARAGE_ADMIN_TOKEN`) from the sops-nix configured
`/etc/kierLeapMount/secrets.yaml` instead of the previous imperative
first-boot provisioning service, and provide a VM test with artificial
secrets. Git branch: `refactor-garage-secret2`.

## Steps undertaken

1. **Inspected the existing configuration**
   - `zeusOlympia/garage/default.nix` provisioned the secrets imperatively at
     first boot via a `garage-rpc-secret.service` oneshot that wrote
     `/var/lib/private/garage/rpc-secret.env`, used as
     `services.garage.environmentFile`.
   - The host's sops setup lives in `zeusOlympia/security/default.nix`
     (imports the sops-nix module, `defaultSopsFile =
     /etc/kierLeapMount/secrets.yaml`, `useSystemdActivation = true`) and
     `zeusOlympia/wranHearst/sops.nix` (existing secret declarations using
     that same file).

2. **Modified `zeusOlympia/garage/default.nix`**
   - Removed the imperative `garage-rpc-secret.service` and the
     `wants`/`after` wiring towards it.
   - Declared two sops secrets read from `/etc/kierLeapMount/secrets.yaml`:
     `garage/rpc-secret` and `garage/admin-token` (mode 0400, with
     `restartUnits` so garage and the layout service restart on rotation).
   - Added a sops template `garage-env` that renders both values into a
     single env file (`/run/secrets/rendered/garage-env`), because the
     upstream garage module takes exactly one `environmentFile` (and its CLI
     wrapper sources the same file).
   - Pointed `services.garage.environmentFile` at
     `config.sops.templates."garage-env".path`.
   - Made `garage.service` order after `sops-install-secrets.service`
     (the unit sops-nix uses when `useSystemdActivation` is enabled, as on
     wranHearst; a harmless no-op on activation-script hosts).
   - Updated `garage-layout.service` to source the sops-rendered env file
     instead of the old `rpc-secret.env`.
   - Documented in comments that the following keys must be added
     imperatively to `/etc/kierLeapMount/secrets.yaml` (nested YAML; sops-nix
     splits secret names on "/"):

     ```yaml
     garage:
       rpc-secret:  <32 random bytes in hex, e.g. head -c 32 /dev/urandom | od -An -tx1 | tr -d " \n">
       admin-token: <random token, e.g. head -c 32 /dev/urandom | base64>
     ```

     Until these keys are added by hand, the service will not work (as
     expected per the task).

3. **Created a VM test with artificial secrets**
   - New file `kaounSlidesTotem/garage-test/default.nix`: a NixOS VM test
     (`pkgs.testers.runNixOSTest`) that:
     - generates a throwaway age keypair and sops-encrypts an artificial
       `secrets.yaml` (nested `garage.rpc-secret` / `garage.admin-token`,
       random values) in a `runCommand` derivation;
     - exposes that encrypted file as `/etc/kierLeapMount/secrets.yaml` on
       the test VM (standing in for the real imperative secrets file) and
       stages the throwaway age key as `sops.age.keyFile` (standing in for
       the host-derived age key from `zeusOlympia/security`);
     - imports the real garage module unchanged (including its impermanence
       persistence declarations) on top of the sops-nix + impermanence
       modules, mirroring the wranHearst setup;
     - asserts, inside the booted VM:
       - the sops-rendered env file exists and contains both variables,
         and the raw decrypted secrets exist under `/run/secrets/garage/`;
       - `garage.service` and `garage-layout.service` start successfully;
       - `/health` responds and the admin API accepts the token from the
         rendered env file (`/v1/status` with `Authorization: Bearer`);
       - the `garage` CLI wrapper works out of the box (`garage status`,
         `garage layout show` shows the wranHearst tag);
       - the S3 API works end-to-end (`garage bucket create test-bucket`,
         `garage bucket list`) and answers on port 3900.
   - Wired the test into the flake as
     `checks.x86_64-linux.garage-vm-test`.

4. **Fixed issues found while iterating on the test**
   - `runCommand` needs an explicit `mkdir -p $out`.
   - sops-nix rejects store paths for `sops.age.keyFile`, so the test key is
     staged into `/var/lib/garage-test-sops/key.txt` by a unit ordered
     before `sops-install-secrets.service` (also enabling
     `useSystemdActivation` like the real host).
   - sops-nix resolves secret names against *nested* YAML keys, so the
     secrets file must use the `garage:` / `rpc-secret:` / `admin-token:`
     nesting (documented in the module comment).
   - The sops template path is `/run/secrets/rendered/<name>` and the admin
     status endpoint is `/v1/status` in garage 1.3.1; adjusted the test
     accordingly and made the garage CLI assertions retry-based (the CLI can
     transiently fail while the layout ring propagates).

5. **Ran and verified the test**
   - `nix build .#checks.x86_64-linux.garage-vm-test` — passes: garage boots
     on the VM with secrets decrypted from the (artificial) sops file, the
     layout is applied, and the S3/admin APIs work.
   - Verified the real host config still evaluates:
     `nix eval .#nixosConfigurations.wranHearst.config.services.garage.environmentFile`
     → `/run/secrets/rendered/garage-env`, with the two new sops secrets
     declared as expected.

## Files changed

- `zeusOlympia/garage/default.nix` — secrets now come from sops-nix
  (`/etc/kierLeapMount/secrets.yaml`); imperative provisioning removed.
- `kaounSlidesTotem/garage-test/default.nix` — new VM test with artificial
  secrets.
- `flake.nix` — new check output `checks.x86_64-linux.garage-vm-test`.

## Remaining manual step

Add the two `garage` keys (nested, as shown above) to
`/etc/kierLeapMount/secrets.yaml` on wranHearst (imperatively, e.g. with
`sops`); until then the garage service will not start.
