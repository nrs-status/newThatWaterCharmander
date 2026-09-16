# Eval tests for the kubernetes (k3s) module. Checks that every host got the
# right cluster configuration. Run with:
#   nix-instantiate --eval --strict --show-trace kaounSlidesTotem/kubernetes/a.nix -A result
with builtins;
let
  lib = flake.inputs.nixpkgs.lib;
  flake = getFlake (toString ../..);
  configs = flake.nixosConfigurations;
  kubernetes = host: configs.${host}.config.kubernetes;
  k3s = host: configs.${host}.config.services.k3s;

  assertEq = name: expected: actual: {
    inherit name expected actual;
    passed = expected == actual;
  };

  checks =
    # control host
    [
      (assertEq "wranHearst is the control host" "control" (kubernetes "wranHearst").role)
      (assertEq "wranHearst runs a k3s server" "server" (k3s "wranHearst").role)
      (assertEq "wranHearst initializes the cluster" true (k3s "wranHearst").clusterInit)
      (assertEq "wranHearst has no serverAddr (it is the server)" "" (k3s "wranHearst").serverAddr)
      (assertEq
        "wranHearst API server is reachable at its MagicDNS (tailnet) address"
        "https://${configs.wranHearst.config.tailnet.magicFqdn}:6443"
        (kubernetes "wranHearst").serverAddr
      )
      (assertEq
        "wranHearst exposes its hostname and MagicDNS (tailnet) name in the TLS SANs"
        [
          "--tls-san wranHearst"
          "--tls-san ${configs.wranHearst.config.tailnet.magicFqdn}"
        ]
        (filter (flag: lib.hasPrefix "--tls-san" flag) (k3s "wranHearst").extraFlags)
      )
      (assertEq
        "wranHearst allows the cluster ports through the firewall"
        true
        (let
          tcp = configs.wranHearst.config.networking.firewall.allowedTCPPorts;
          udp = configs.wranHearst.config.networking.firewall.allowedUDPPorts;
        in
          all (p: elem p tcp) [ 6443 10250 2379 2380 ] && all (p: elem p udp) [ 8472 ]
        )
      )
      # impermanence coerces plain strings to directory submodules
      (assertEq
        "wranHearst persists its cluster state"
        true
        (let
          persisted = map (dir: dir.directory or dir) configs.wranHearst.config.environment.persistence."/persist".directories;
        in
          all (dir: elem dir persisted) [
            "/var/lib/rancher"
            "/var/lib/kubelet"
            "/etc/rancher"
          ]
        )
      )
    ]
    # worker hosts
    ++ (map
      (
        host:
        assertEq "${host} is a worker" "worker" (kubernetes host).role
      )
      [
        "lanchamarcou"
        "augtibcalcla"
      ]
    )
    ++ (map
      (
        host:
        assertEq "${host} runs a k3s agent" "agent" (k3s host).role
      )
      [
        "lanchamarcou"
        "augtibcalcla"
      ]
    )
    ++ (map
      (
        host:
        assertEq "${host} registers with the wranHearst control host over the tailnet" "https://${configs.wranHearst.config.tailnet.magicFqdn}:6443" (k3s host).serverAddr
      )
      [
        "lanchamarcou"
        "augtibcalcla"
      ]
    )
    ++ (map
      (
        host:
        assertEq "${host} does not try to initialize a cluster" false (k3s host).clusterInit
      )
      [
        "lanchamarcou"
        "augtibcalcla"
      ]
    )
    ++ (map
      (
        host:
        assertEq "${host} uses the shared cluster token" (kubernetes "wranHearst").clusterToken (k3s host).token
      )
      [
        "lanchamarcou"
        "augtibcalcla"
      ]
    );

  failedChecks = filter (check: !check.passed) checks;
  passedChecks = filter (check: check.passed) checks;
in
{
  result =
    if failedChecks == [ ] then
      "all ${toString (length passedChecks)} kubernetes module eval checks passed"
    else
      throw "kubernetes module eval checks failed:\n${concatStringsSep "\n" (map (check: "  ${check.name}: expected ${toJSON check.expected}, got ${toJSON check.actual}") failedChecks)}";
}
