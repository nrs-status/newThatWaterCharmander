# Kubernetes cluster configuration, built on k3s.
#
# The cluster consists of:
#   - `wranHearst`: control host (k3s server, bootstraps the cluster)
#   - `lanchamarcou` and `augtibcalcla`: worker hosts (k3s agents)
#
# Every host includes this module and sets `kubernetes.role` accordingly
# (see the kubernetes.nix file in each host directory).
{ config, lib, ... }:
let
  cfg = config.kubernetes;
  # MagicDNS FQDN of the control host (wranHearst.<baseDomain>, served by the
  # headscale tailnet; see ../headscale). the tailnet module is imported by
  # every host of the repo; guarded so standalone imports (e.g. the cluster
  # VM test in ../../kaounSlidesTotem/kubernetes) still evaluate.
  magicFqdn =
    if config ? tailnet then config.tailnet.magicFqdn else null;
in
{
  options.kubernetes = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable the Kubernetes (k3s) cluster node on this host.
        Set to `false` to disable the module entirely, even when imported.
      '';
    };

    role = lib.mkOption {
      type = lib.types.enum [
        "control"
        "worker"
      ];
      description = ''
        Role of this node in the cluster: `control` runs the k3s server (and
        initializes the cluster), `worker` runs a k3s agent that registers with
        the control host.
      '';
    };

    serverAddr = lib.mkOption {
      type = lib.types.str;
      # the workers reach the control host over the headscale tailnet via its
      # MagicDNS name (see ../headscale); without the tailnet module (e.g. the
      # standalone cluster VM test) the plain hostname is kept
      default =
        if config ? tailnet then "https://${config.tailnet.magicFqdn}:6443" else "https://wranHearst:6443";
      description = "Address of the control host's k3s API server, used by workers to join the cluster.";
    };

    serverName = lib.mkOption {
      type = lib.types.str;
      default = "wranHearst";
      description = ''
        DNS name of the control host. It is added to the API server's TLS
        SANs (plain, and the MagicDNS FQDN of the headscale tailnet, see
        ../headscale) so that workers can connect by name.
      '';
    };

    clusterToken = lib.mkOption {
      type = lib.types.str;
      default = "wranHearst::k3s-cluster-token::replace-with-sops-managed-secret";
      description = ''
        Shared cluster token. WARNING: this placeholder ends up world-readable
        in the nix store; override it (e.g. with a sops-nix managed
        `tokenFile`) for real deployments.
      '';
    };

    nodeIP = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "IP address k3s advertises for this node; detected automatically when null.";
    };

    extraFlags = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
      description = "Extra flags passed to the k3s command on this node.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.k3s = {
      enable = true;
      role = if cfg.role == "control" then "server" else "agent";
      # the control host bootstraps the cluster; workers just join it
      clusterInit = cfg.role == "control";
      serverAddr = lib.mkIf (cfg.role == "worker") cfg.serverAddr;
      token = cfg.clusterToken;
      nodeIP = lib.mkIf (cfg.nodeIP != null) cfg.nodeIP;
      extraFlags =
        cfg.extraFlags
        ++ lib.optionals (cfg.role == "control") (
          [
            "--tls-san ${cfg.serverName}"
          ]
          ++ lib.optionals (config ? tailnet) [
            "--tls-san ${config.tailnet.magicFqdn}" # MagicDNS name, headscale tailnet
          ]
        );
    };

    # Keeps the k3s cluster state across reboots.
    environment.persistence."/persist".directories = [
      "/var/lib/rancher"
      "/var/lib/kubelet"
      "/etc/rancher"
    ];

    # provides `k3s kubectl` for cluster administration
    environment.systemPackages = [ config.services.k3s.package ];

    # cluster communication:
    # 6443: k8s API server, 10250: kubelet, 2379/2380: embedded etcd (for
    # future HA control hosts), 8472/udp: flannel VXLAN overlay network
    networking.firewall.allowedTCPPorts = [
      6443
      10250
    ]
    ++ lib.optionals (cfg.role == "control") [
      2379
      2380
    ];
    networking.firewall.allowedUDPPorts = [ 8472 ];
  };
}
