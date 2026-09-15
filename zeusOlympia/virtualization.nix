{ pkgs, ... }:
{
  virtualisation = {
    libvirtd = {
      enable = true;
      qemu = {
        package = pkgs.qemu_kvm;
        runAsRoot = true;
        swtpm.enable = true;
      };
    };
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };
  };

  # the hosts run impermanence (root is wiped on reboot), so the virtualization
  # state must be persisted explicitly; declared here, inside the service module
  # (same pattern as ./garage, ./openBao, ./vaultWarden, ./kubernetes):
  # - /var/lib/libvirt: VM disk images, libvirt's dnsmasq/secrets/swtpm state
  #   (see virtualisation.libvirtd.qemu.swtpm.enable above)
  # - /var/lib/containers: podman's graph root (image/container storage and
  #   netavark network state); shared by the podman module and
  #   virtualisation.containers
  environment.persistence."/persist".directories = [
    "/var/lib/libvirt"
    "/var/lib/containers"
  ];
}
