# Summary: Testing the `louSelfHit-sofa` → `heg-twPlant` refactor

Branch: `add-heg-tweOnPlant` (base: `main` at `21cd59d`)

## What the refactor does (commits 9f70f12, 6b4c930)

Common configuration was moved out of `empTriageCan/louSelfHit-sofa` into a new
shared module directory `empTriageCan/heg-twPlant`:

- `misc.nix`, `nix.nix`, `openssh.nix`, `security/` moved from `louSelfHit-sofa/` to `heg-twPlant/` (only comment tweaks changed).
- A new `heg-twPlant/packages.nix` holds the packages previously in `louSelfHit-sofa/packages.nix` (vim, git, curl, encryption tools, unix-tool replacements, …); `louSelfHit-sofa/packages.nix` keeps only keyd, brightnessctl, pciutils, usbutils.
- `louSelfHit-sofa/default.nix` now imports `../heg-twPlant`, which also imports `localModules.console`, `localModules.headscale`, `localModules.bootIntrospection` (moved from `louSelfHit-sofa/default.nix`).
- `empTriageCan/default.nix` extends its host-module predicate to (intend to) exclude `heg-twPlant` from being treated as a host.

## Steps undertaken

1. **Read the repo and the diff.** Inspected `flake.nix`, `empTriageCan/*`, `heidRunOverCar/mkNixosSystems.nix`, `mkDirectoryImporterModule.nix`, and the base-lib helpers (`importPairsOfDirPath`, `listPathsSatisfyingPred` in the `peachRampSkateboard` input) to understand how module directories become hosts.

2. **Found a real bug introduced by the refactor.** In `empTriageCan/default.nix` the predicate read
   `baseNameOf != "heg-twPlant"` — it compared the *function* `baseNameOf` to a string, which in Nix evaluates to `true`, so the intended exclusion was a no-op.
   Consequence: `heg-twPlant` leaked into the flake as a spurious host:
   - `nixosConfigurations` had 10 entries (main has 9), including an extra `heg-twPlant`.
   - `colmenaHive.nodes` included a spurious `heg-twPlant` node.

3. **Fixed the bug** (uncommitted, per instructions): `baseNameOf != "heg-twPlant"` → `baseNameOf x != "heg-twPlant"`.

4. **Re-checked entry sets.** After the fix, `nixosConfigurations` and `colmenaHive.nodes` match `main` exactly (9 configurations; colmena nodes `augtibcalcla`, `lanchamarcou`).

5. **Evaluated every host on both branches** (worktree of `main` in /tmp, removed afterwards) and compared `config.system.build.toplevel.drvPath` for all 9 hosts (`augtibcalcla`, `lanchamarcou`, `wH-full`, `wH-small-2GB/3GB/5GB`, `wranHearst`, `wranHearst-gui`, `wranHearst-minimal`). All drv hashes differ — investigated why.

6. **Exhaustive recursive derivation-graph diff** for each host (custom walker over `nix derivation show`): every differing derivation was classified. All 9 hosts reported **OK — every difference is a pure reorder or a reference to an already-explained rebuild**. The single root cause: the refactor splits `environment.systemPackages` across two modules, so the *evaluation order* of the same package set changed inside the `system-path` buildEnv derivation.

7. **Proved the reordering is content-identical**: built both `system-path` variants and `diff -r` reported **zero differences** (byte-identical trees, same package set).

8. **End-to-end build check**: built both `augtibcalcla` toplevels (main + branch) and compared the resulting `/etc` trees entry-by-entry with symlink dereferencing: **no missing entries and no content differences**.

9. **Checked the remaining flake outputs**:
   - `checks.x86_64-linux`: all 7 VM-test derivations are **bit-identical** between `main` and the branch.
   - `colmenaHive` node toplevels: identical to the already-verified `nixosConfigurations` toplevels.

## Conclusion

- The refactor's intended behaviour change (shared module dir, same effective config for all hosts) is **verified behaviour-preserving** for every host, colmena node and VM test.
- The refactor as committed contained a **predicate bug** (`baseNameOf` vs `baseNameOf x`) that silently added a spurious `heg-twPlant` nixosConfiguration and colmena node; fixed in `empTriageCan/default.nix` (left uncommitted).
- Only cosmetic store-path changes remain (package-list ordering inside `system-path`); built content is byte-identical.
