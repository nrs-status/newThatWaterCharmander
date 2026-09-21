# Eval tests for the kubernetes (k3s) module's `enable` option. Checks that
# `kubernetes.enable = false` makes the module a no-op for an importing host,
# while the default (`true`) keeps the previous behavior. Run with:
#   nix-instantiate --eval --strict --show-trace kaounSlidesTotem/kubernetes/enableEvalTest.nix -A result
with builtins;
let
  flake = getFlake (toString ../..);
  lib = flake.inputs.nixpkgs.lib;

  # evaluate the kubernetes module standalone with the given settings
  eval =
    { enable ? null }:
    lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ../../zeusOlympia/kubernetes
        # the module sets environment.persistence, provided by impermanence
        flake.inputs.impermanenceFlake.nixosModules.impermanence
        (
          { kubernetes.role = "control"; }
          // (if enable == null then { } else { kubernetes.enable = enable; })
        )
      ];
    };

  disabled = eval { enable = false; };
  enabled = eval { enable = true; };
  default = eval { };

  assertEq = name: expected: actual: {
    inherit name expected actual;
    passed = expected == actual;
  };

  checks =
    # enable = false must disable everything the module configures
    [
      (assertEq "enable=false sets kubernetes.enable to false" false disabled.config.kubernetes.enable)
      (assertEq "enable=false does not enable k3s" false disabled.config.services.k3s.enable)
      (assertEq
        "enable=false adds no k3s-related firewall TCP ports"
        [ ]
        (filter (p: elem p [ 6443 10250 2379 2380 ]) disabled.config.networking.firewall.allowedTCPPorts)
      )
      (assertEq
        "enable=false adds no k3s-related firewall UDP ports"
        [ ]
        (filter (p: p == 8472) disabled.config.networking.firewall.allowedUDPPorts)
      )
      (assertEq
        "enable=false persists no cluster state directories"
        [ ]
        (let
          persisted = disabled.config.environment.persistence or { };
          persistDirs = map (dir: dir.directory or dir) (persisted."/persist".directories or [ ]);
        in
          filter (dir: elem dir [ "/var/lib/rancher" "/var/lib/kubelet" "/etc/rancher" ]) persistDirs
        )
      )
      # the default keeps the previous behavior
      (assertEq "default enable is true" true default.config.kubernetes.enable)
      (assertEq "enable=true (default) enables k3s" true default.config.services.k3s.enable)
      (assertEq "enable=true (default) runs a k3s server" "server" default.config.services.k3s.role)
      (assertEq "enable=true explicitly also enables k3s" true enabled.config.services.k3s.enable)
    ];

  failedChecks = filter (check: !check.passed) checks;
  passedChecks = filter (check: check.passed) checks;
in
{
  result =
    if failedChecks == [ ] then
      "all ${toString (length passedChecks)} kubernetes enable-option checks passed"
    else
      throw "kubernetes enable-option checks failed:\n${concatStringsSep "\n" (map (check: "  ${check.name}: expected ${toJSON check.expected}, got ${toJSON check.actual}") failedChecks)}";
}
