# VM test for the xandikos module (see ../../zeusOlympia/xandikos/default.nix).
#
# xandikos needs no secrets (no sops file), so this test is simpler than the
# garage/vaultwarden ones: the machine imports the xandikos module unchanged
# (including its impermanence persistence declaration) and must come up fully
# working, with the default calendar and address book autocreated on first
# start.
#
# run with: nix build .#checks.x86_64-linux.xandikos-vm-test
{
  pkgsLib,
  nixpkgsFlake,
  impermanenceFlake,
}:
let
  pkgs = import nixpkgsFlake { system = "x86_64-linux"; };
in
pkgs.testers.runNixOSTest {
  name = "xandikos-caldav";

  nodes.machine =
    { ... }:
    {
      imports = [
        impermanenceFlake.nixosModules.impermanence
        ../../zeusOlympia/xandikos # the xandikos module under test
      ];

      networking.hostName = "xandikosTestVm";

      virtualisation = {
        graphics = false;
        memorySize = 2048;
      };
    };

  testScript = ''
    machine.wait_for_unit("xandikos.service")

    # the upstream module runs with DynamicUser=true and StateDirectory=
    # xandikos, so the real state directory is /var/lib/private/xandikos
    machine.succeed("test -d /var/lib/private/xandikos")

    # --defaults must have autocreated the principal with a default calendar
    # and address book (git-backed collections)
    machine.succeed("test -d /var/lib/private/xandikos/sieyes/calendars/calendar")
    machine.succeed("test -d /var/lib/private/xandikos/sieyes/contacts/addressbook")

    # the web UI must answer on the configured port
    machine.wait_for_open_port(8330)
    machine.succeed("curl -sf http://127.0.0.1:8330/ | grep -qi xandikos")

    # CalDAV end-to-end: PUT an event into the default calendar, then GET it
    # back. a CalDAV collection answers PROPFIND with 207 (multi-status)
    machine.succeed(
        "curl -sf -X PROPFIND -H 'Depth: 0' -o /dev/null "
        "-w '%{http_code}' http://127.0.0.1:8330/sieyes/calendars/calendar/ "
        "| grep -q '^207$'"
    )
    machine.succeed(
        "curl -sf -X PUT -H 'Content-Type: text/calendar' "
        "--data-binary 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//EN\r\n"
        "BEGIN:VEVENT\r\nUID:test-event-1\r\nDTSTART:20260926T120000Z\r\n"
        "SUMMARY:xandikos-vm-test\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n' "
        "http://127.0.0.1:8330/sieyes/calendars/calendar/test-event-1.ics"
    )
    machine.succeed(
        "curl -sf http://127.0.0.1:8330/sieyes/calendars/calendar/test-event-1.ics "
        "| grep -q xandikos-vm-test"
    )

    # the service listens on all interfaces (firewall port is open), so the
    # server is reachable from the LAN / the headscale tailnet
    machine.succeed("ss -tlnp | grep -q '0.0.0.0:8330'")
  '';
}
