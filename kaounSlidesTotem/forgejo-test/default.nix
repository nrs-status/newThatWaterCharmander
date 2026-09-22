# VM test for the forgejo module (see ../../zeusOlympia/forgejo/default.nix).
#
# like the media test this needs no artificial secrets: the forgejo module
# only declares services, the CLI wrapper and impermanence persistence for
# the forgejo state dir. the machine imports the module unchanged together
# with the impermanence module and the shared tailnet options (the module
# reads tailnet.baseDomain/magicFqdn for the account emails and ROOT_URL)
# and must come up fully working:
#
#   - forgejo-user-passwords.service runs UNPRIVILEGED (User/Group =
#     the forgejo user, not root) and still generates a random password
#     file per account on first boot, owned forgejo:forgejo with the same
#     permissions the previous root-run variant produced (dir 0700 via
#     UMask 0077, files 0600, no chown needed)
#   - forgejo.service comes up, its preStart provisions the admin
#     (wranHearst) and the regular users from the generated password files
#     and the web UI is reachable on port 3000
#   - the generated passwords really work: logging into the web UI with
#     the content of each password file succeeds
#   - the CLI wrapper lets the operator list the accounts exactly as
#     documented in the module (sudo -u forgejo forgejo admin user list)
#   - the ConditionPathExists guard preserves password stability: a manual
#     re-run of the unit is skipped and the files keep their content, and
#     the same holds across a reboot
#   - the password dir is persisted under /persist (survives the
#     root-on-btrfs wipe on wranHearst)
#
# run with: nix build .#checks.x86_64-linux.forgejo-vm-test
{
  pkgsLib,
  nixpkgsFlake,
  impermanenceFlake,
}:
let
  pkgs = import nixpkgsFlake { system = "x86_64-linux"; };
in
pkgs.testers.runNixOSTest {
  name = "forgejo-unprivileged-user-passwords-vm-test";

  nodes.machine =
    {
      imports = [
        impermanenceFlake.nixosModules.impermanence
        ../../zeusOlympia/headscale/tailnet.nix # shared tailnet.* options used by the forgejo module
        ../../zeusOlympia/forgejo # the forgejo module under test (incl. its impermanence declarations)
      ];

      networking.hostName = "forgejoTestVm";

      environment.persistence."/persist".hideMounts = true;

      virtualisation = {
        graphics = false;
        memorySize = 4096;
        diskSize = 8192;
      };
    };

  testScript = ''
    password_dir = "/var/lib/forgejo/user-passwords"

    # the accounts the module provisions: the administrator first, then the
    # regular users (mirrors ../../zeusOlympia/forgejo/default.nix)
    users = ["wranHearst", "sieyes", "plat2548", "soc7099"]

    def digest(user):
        return machine.succeed(f"sha256sum {password_dir}/{user}").split()[0]

    # ------------------------------------------------------------------
    # the password unit must be configured unprivileged (the whole point
    # of this change) and succeed on first boot
    # ------------------------------------------------------------------
    # it is a oneshot that finishes before multi-user.target is reached,
    # so wait for the target and for the generated files instead of the
    # unit being "active"
    machine.wait_for_unit("multi-user.target", timeout=600)
    for u in users:
        machine.wait_until_succeeds(f"test -s {password_dir}/{u}", timeout=120)

    # it must really have run to completion this boot (the guard directory
    # did not exist on first boot, so the condition did not skip it)
    assert (
        machine.succeed(
            "systemctl show forgejo-user-passwords.service -p Result --value"
        ).strip()
        == "success"
    ), "forgejo-user-passwords.service did not succeed"
    assert (
        machine.succeed(
            "systemctl show forgejo-user-passwords.service -p ExecMainStatus --value"
        ).strip()
        == "0"
    ), "forgejo-user-passwords.service exited nonzero"
    start_ts = machine.succeed(
        "systemctl show forgejo-user-passwords.service -p ExecMainStartTimestamp --value"
    ).strip()
    assert start_ts not in ("", "n/a"), "unit did not run this boot"

    # ------------------------------------------------------------------
    # the password unit must be configured unprivileged (the whole point
    # of this change)
    # ------------------------------------------------------------------
    user = machine.succeed(
        "systemctl show forgejo-user-passwords.service -p User --value"
    ).strip()
    group = machine.succeed(
        "systemctl show forgejo-user-passwords.service -p Group --value"
    ).strip()
    assert user == "forgejo", f"unit must run as forgejo, not {user!r}"
    assert group == "forgejo", f"unit group must be forgejo, not {group!r}"

    # ...and the files it generated are owned by the forgejo user, with the
    # same layout the old root-run variant produced: dir 0700
    # forgejo:forgejo, files 0600 forgejo:forgejo (UMask 0077, no chown)
    out = machine.succeed(f"stat -c '%U:%G %a' {password_dir}").strip()
    assert out == "forgejo:forgejo 700", f"bad password dir: {out!r}"
    for u in users:
        out = machine.succeed(f"stat -c '%U:%G %a' {password_dir}/{u}").strip()
        assert out == "forgejo:forgejo 600", f"bad password file {u}: {out!r}"
    # nothing in the tree may be root-owned any more
    out = machine.succeed(f"find {password_dir} ! -user forgejo | head -n1")
    assert out.strip() == "", f"root-owned entries remain: {out!r}"

    print("USER PASSWORDS UNIT: unprivileged and successful")

    # ------------------------------------------------------------------
    # forgejo comes up and provisions the accounts from those files
    # ------------------------------------------------------------------
    machine.wait_for_unit("forgejo.service", timeout=600)
    machine.wait_for_open_port(3000, timeout=300)
    machine.succeed("curl -sf http://127.0.0.1:3000/ -o /dev/null")

    def admin_user_list():
        # exactly the documented operator path: the wrapper locates the
        # config through the unit's environment, run as the forgejo user
        return machine.succeed(
            "su -s /bin/sh forgejo -c "
            "'/run/current-system/sw/bin/forgejo admin user list'"
        )

    listing = admin_user_list()
    print("USER LIST:", listing)
    for u in users:
        assert u in listing, f"{u} was not provisioned by forgejo preStart: {listing}"

    # ------------------------------------------------------------------
    # the generated passwords actually work: web UI login with the file
    # content succeeds (302 redirect), a wrong password is rejected
    # ------------------------------------------------------------------
    def web_login(user, password):
        # the login form of this forgejo version carries no _csrf field
        # (verified: the form only has user_name/password/remember), so a
        # plain form POST is enough
        status, out = machine.execute(
            "curl -s -o /dev/null -w '%{http_code}' "
            f"--data-urlencode 'user_name={user}' "
            f"--data-urlencode 'password={password}' "
            "http://127.0.0.1:3000/user/login"
        )
        return out.strip()

    for u in users:
        password = machine.succeed(f"cat {password_dir}/{u}").strip()
        assert password, f"empty password file for {u}"
        assert web_login(u, password) in ("302", "303"), (
            f"web login with the generated password failed for {u}"
        )
    assert web_login("sieyes", "definitely-not-the-password") == "200", (
        "a wrong password must not log in"
    )
    print("WEB LOGIN: generated passwords work for all accounts")

    # ------------------------------------------------------------------
    # password stability: re-running the unit must be skipped by its
    # ConditionPathExists guard and leave the files untouched
    # ------------------------------------------------------------------
    digests_before = {u: digest(u) for u in users}
    mtimes_before = {
        u: machine.succeed(f"stat -c %Y {password_dir}/{u}").strip() for u in users
    }
    machine.succeed("systemctl restart forgejo-user-passwords.service")
    out = machine.succeed(
        "systemctl show forgejo-user-passwords.service -p Result --value"
    ).strip()
    assert out == "success", out
    digests_after = {u: digest(u) for u in users}
    mtimes_after = {
        u: machine.succeed(f"stat -c %Y {password_dir}/{u}").strip() for u in users
    }
    assert digests_before == digests_after, "passwords changed on a re-run"
    assert mtimes_before == mtimes_after, "password files were rewritten on a re-run"

    # ------------------------------------------------------------------
    # persistence + boot stability: reboot and confirm the passwords
    # survive (bind mount from /persist) and are NOT regenerated (the
    # ConditionPathExists guard also skips on the new boot), so the same
    # accounts still authenticate
    # ------------------------------------------------------------------
    machine.succeed("test -d /persist" + password_dir)

    machine.shutdown()
    machine.start()
    machine.wait_for_unit("multi-user.target", timeout=600)
    machine.wait_for_unit("forgejo.service", timeout=600)
    machine.wait_for_open_port(3000, timeout=300)

    digests_reboot = {u: digest(u) for u in users}
    assert digests_before == digests_reboot, (
        f"passwords did not survive the boot unchanged: "
        f"{digests_before} vs {digests_reboot}"
    )

    for u in users:
        password = machine.succeed(f"cat {password_dir}/{u}").strip()
        assert web_login(u, password) in ("302", "303"), (
            f"web login failed for {u} after reboot"
        )
    print("REBOOT: passwords persisted and still valid")
  '';
}
