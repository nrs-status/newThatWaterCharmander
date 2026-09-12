# Enables the Garage object store on this host.
#
# The secret files below are build-time placeholders kept in the Nix store;
# before putting real data on this instance they should be replaced by
# sops-managed secret files (see zeusOlympia/wranHearst/sops.nix for the
# sops wiring pattern).
{ pkgs, ... }:
{
  services.garage = {
    enable = true;

    rpcSecretFile = pkgs.writeText "garage-rpc-secret" "013e986b23e39aa41e15a68dd6dbf95672ff4d256ddfe0a204a4bd9055ab619f";
    adminTokenFile = pkgs.writeText "garage-admin-token" "NrWcw4k2+zukJAPmODSX8HeyLMm6+5rXrqyOuU1IqeQ";
  };
}
