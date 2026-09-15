# Boots a three-node k3s cluster in VMs (1 control host + 2 workers) using the
# kubernetes module from this flake, and checks that both workers register with
# the control host and become Ready. Run with:
#   nix-build kaounSlidesTotem/kubernetes/clusterVmTest.nix
#   ./result/bin/wranhearst-kubernetes-cluster
with builtins;
let
  flake = getFlake (toString ../..);
  pkgs = flake.inputs.nixpkgs.legacyPackages.x86_64-linux;
  kubernetesModule = ../../zeusOlympia/kubernetes;

  # reduced resource usage / no image pulls needed, same as nixpkgs' k3s tests
  disableFlags = map (component: "--disable ${component}") [
    "coredns"
    "local-storage"
    "metrics-server"
    "servicelb"
    "traefik"
  ];
  vmResources = {
    memorySize = 2048;
    diskSize = 4096;
    cores = 2;
  };

in
pkgs.testers.nixosTest {
  name = "wranhearst-kubernetes-cluster";

  nodes = {
    control = { config, ... }:
      {
        imports = [ kubernetesModule ];
        kubernetes = {
          role = "control";
          nodeIP = config.networking.primaryIPAddress;
          extraFlags = [ "--flannel-iface eth1" ]  ++ [];
        };
        virtualisation = vmResources;
      };
    agent1 = { nodes, config, ... }:
      {
        imports = [ kubernetesModule ];
        kubernetes = {
          role = "worker";
          serverAddr = "https://${nodes.control.networking.primaryIPAddress}:6443";
          nodeIP = config.networking.primaryIPAddress;
          extraFlags = [ "--flannel-iface eth1" ];
        };
        virtualisation = vmResources;
      };
    agent2 = { nodes, config, ... }:
      {
        imports = [ kubernetesModule ];
        kubernetes = {
          role = "worker";
          serverAddr = "https://${nodes.control.networking.primaryIPAddress}:6443";
          nodeIP = config.networking.primaryIPAddress;
          extraFlags = [ "--flannel-iface eth1" ];
        };
        virtualisation = vmResources;
      };
  };

  testScript = ''
    start_all()

    control.wait_for_unit("k3s")
    control.wait_until_succeeds("test -f /etc/rancher/k3s/k3s.yaml")

    for agent in (agent1, agent2):
        agent.wait_for_unit("k3s")

    # both workers register with the control host
    control.wait_until_succeeds("k3s kubectl get node agent1")
    control.wait_until_succeeds("k3s kubectl get node agent2")

    # all nodes, including the control host's own agent, become Ready
    for node in ("control", "agent1", "agent2"):
        control.succeed(f"k3s kubectl wait --timeout=600s --for=condition=Ready node/{node}")

    control.succeed("k3s kubectl get nodes -o wide")
  '';
}
