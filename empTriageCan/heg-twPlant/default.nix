{ localLib, localModules, ... }:
{
  imports = [
    (localLib.mkDirectoryImporterModule ./.)

    localModules.console
    localModules.headscale # tailnet/MagicDNS discovery (self-gating per hostname)
    localModules.bootIntrospection # persistent journald + systemd initrd (required by fs/impermanence rollback)
  ];
}
