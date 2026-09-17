# wranHearst is the control host of the k3s cluster
{ localModules, ... }:
{
  imports = [ localModules.kubernetes ];
  kubernetes.role = "control";
}
