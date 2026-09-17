{ localLib, localModules, ... }:
{
  imports = [
    ./security
    (localLib.mkDirectoryImporterModule ./.)

    # modules that every host imported in the pre-refactor (main) configuration
    localModules.headscale # tailnet/MagicDNS discovery (self-gating per hostname)
    localModules.bootIntrospection # persistent journald + systemd initrd (required by fs/impermanence rollback)
  ];
}
