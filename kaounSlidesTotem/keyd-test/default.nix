# VM test for the keyd key-remapping module
# (see ../../empTriageCan/louSelfHit-sofa/keyRemappings.nix).
#
# The module remaps a/s/d with `overloadt` (hold -> meta/alt/control, tap ->
# letter) and adds a runtime toggle: pressing the toggle key (option
# `keyRemappings.lhsHomerowToggleKey`, default f21) permanently
# toggles the `lhsOff` layer, whose identity bindings (a = a, s = s, d = d)
# occlude the main-layer overloadt remaps, returning the keys to normal use;
# pressing it again restores the remaps.
#
# Verified here:
#
#   - the generated /etc/keyd/default.conf has the a/s/d overloadt remaps in
#     main, the identity bindings in the [lhsOff] layer and the
#     `toggle(lhsOff)` binding on the toggle key; the other remaps
#     (rightalt -> f13, capslock layer, f/h/j/k/l, number shifts) are intact
#   - keyd.service runs with that config in both nodes (keyd validates the
#     config at startup)
#   - a custom `lhsHomerowToggleKey` is honored (second node, bound to
#     `insert` instead of the default `f21`)
#   - keyd reports a pressed f21 as `f21`: with the daemon stopped (it
#     EVIOCGRABs its devices, so a monitor running alongside it would see
#     nothing), `keyd monitor` receives an f21 press injected through evemu
#     and prints `... f21 down` / `... f21 up`
#   - END-TO-END: a second virtual keyboard is created with evemu-device
#     (keyd grabs it, ids = "*") and keys are injected with evemu-event;
#     keyd's *output* device ("keyd virtual keyboard") is recorded with
#     evtest. Holding `a` and tapping `l`
#
#       * with the remaps active emits KEY_LEFTMETA (and no KEY_A), i.e.
#         super+l  — twice (initially, and again after toggling off)
#       * after one f21 press emits plain KEY_A + KEY_L and no
#         KEY_LEFTMETA (a/s/d back to normal)
#
#     and `keyd listen` reports exactly one `+lhsOff` / `-lhsOff` layer
#     state change per f21 press.
#
#     (QEMU's sendkey cannot hold keys across monitor commands and has no
#     f21 key, which is why all key injection goes through evemu.)
#
# run with: nix build .#checks.x86_64-linux.keyd-vm-test
{
  pkgsLib,
  nixpkgsFlake,
}:
let
  pkgs = import nixpkgsFlake { system = "x86_64-linux"; };
in
pkgs.testers.runNixOSTest {
  name = "keyd-vm-test";

  nodes = {
    machine =
      { ... }:
      {
        imports = [ ../../empTriageCan/louSelfHit-sofa/keyRemappings.nix ];
        # lhsHomerowToggleKey defaults to "f21"

        networking.hostName = "keydVm";
        virtualisation.graphics = false;
        environment.systemPackages = [
          pkgs.evtest
          pkgs.evemu
        ];
      };

    customToggleKey =
      { ... }:
      {
        imports = [ ../../empTriageCan/louSelfHit-sofa/keyRemappings.nix ];
        keyRemappings.lhsHomerowToggleKey = "insert";

        networking.hostName = "keydCustomToggleVm";
        virtualisation.graphics = false;
      };
  };

  testScript = ''
    start_all()

    # ------------------------------------------------------------------
    # keyd runs with the generated config (it validates the config at
    # startup, so a broken binding would crash the unit here)
    # ------------------------------------------------------------------
    for vm in (machine, customToggleKey):
        vm.wait_for_unit("keyd.service")
        vm.succeed("systemctl is-active keyd.service")

    conf = "/etc/keyd/default.conf"

    for vm in (machine, customToggleKey):
        # the a/s/d overloadt remaps are active by default (daemon start state)
        vm.succeed(f"grep -q 'a=overloadt(meta, a, 130)' {conf}")
        vm.succeed(f"grep -q 's=overloadt(alt, s, 130)' {conf}")
        vm.succeed(f"grep -q 'd=overloadt(control, d, 130)' {conf}")

        # the occluding [lhsOff] layer exists
        vm.succeed(f"grep -A3 '^\\[lhsOff\\]$' {conf} | grep -q '^a=a$'")
        vm.succeed(f"grep -A3 '^\\[lhsOff\\]$' {conf} | grep -q '^s=s$'")
        vm.succeed(f"grep -A3 '^\\[lhsOff\\]$' {conf} | grep -q '^d=d$'")

        # every non-a/s/d remapping is untouched
        vm.succeed(f"grep -q 'leftcontrol=capslock' {conf}")
        vm.succeed(f"grep -q 'rightalt=f13' {conf}")
        vm.succeed(f"grep -q 'capslock=layer(custom2)' {conf}")
        vm.succeed(f"grep -q 'f=overloadt(shift, f, 130)' {conf}")
        vm.succeed(f"grep -q 'h=overloadt(shift, h, 130)' {conf}")
        vm.succeed(f"grep -q 'j=overloadt(control, j, 130)' {conf}")
        vm.succeed(f"grep -q 'k=overloadt(alt, k, 130)' {conf}")
        vm.succeed(f"grep -q 'l=overloadt(meta, l, 130)' {conf}")
        vm.succeed(f"grep -q '1=!' {conf}")

    # the default toggle key
    machine.succeed(f"grep -q 'f21=toggle(lhsOff)' {conf}")

    # the toggle key option is honored
    customToggleKey.succeed(f"grep -q 'insert=toggle(lhsOff)' {conf}")
    customToggleKey.fail(f"grep -q 'f21=toggle(lhsOff)' {conf}")

    # ------------------------------------------------------------------
    # a second virtual keyboard, used to inject keys (keyd grabs it:
    # ids "*"). NB: the description is based on keyd's own output device,
    # so the vendor id (0fac) must be rewritten — keyd ignores every device
    # with its own vendor id to avoid grabbing its output devices
    # ------------------------------------------------------------------
    sysfsName = machine.succeed(
      "grep -l 'keyd virtual keyboard' /sys/class/input/event*/device/name | head -1"
    ).strip()
    evdev = "/dev/input/" + sysfsName.split("/")[-3]
    print(f"keyd output device: {evdev}")

    machine.succeed(
        f"${pkgs.evemu}/bin/evemu-describe {evdev} | sed -e 's/^N: .*/N: testkbd/' -e 's/^I: .*/I: 0003 1234 5678 0001/' > /tmp/testkbd.desc"
    )
    machine.execute("nohup ${pkgs.evemu}/bin/evemu-device /tmp/testkbd.desc > /tmp/evemu.log 2>&1 &")
    machine.sleep(2)

    sysfsName = machine.succeed(
      "grep -l 'testkbd' /sys/class/input/event*/device/name | head -1"
    ).strip()
    testkbd = "/dev/input/" + sysfsName.split("/")[-3]
    print(f"test keyboard: {testkbd}")

    def press(code, value):
        machine.succeed(
            f"${pkgs.evemu}/bin/evemu-event {testkbd} --sync --type 1 --code {code} --value {value}"
        )

    def tapF21():
        press(191, 1)  # KEY_F21 down
        press(191, 0)  # KEY_F21 up
        machine.sleep(1)

    # ------------------------------------------------------------------
    # keyd reports the pressed key as f21: `keyd monitor` prints
    # "<device>\t<id>\t<key> down|up" for raw device events. The daemon
    # must be stopped for this: it EVIOCGRABs the devices, which blocks
    # every other reader
    # ------------------------------------------------------------------
    machine.succeed("systemctl stop keyd.service")
    machine.execute("nohup ${pkgs.keyd}/bin/keyd monitor > /tmp/monitor.log 2>&1 &")
    machine.sleep(2)
    tapF21()
    machine.succeed("grep -q 'testkbd.*f21 down' /tmp/monitor.log")
    machine.succeed("grep -q 'testkbd.*f21 up' /tmp/monitor.log")
    # not reported under its alias or anything else
    machine.fail("grep -q 'prog1' /tmp/monitor.log")
    machine.succeed("pkill -x keyd || true")
    machine.succeed("systemctl start keyd.service")
    machine.wait_for_unit("keyd.service")

    # ------------------------------------------------------------------
    # end-to-end: held-key behavior through the real input path
    # ------------------------------------------------------------------
    evtestLog = "/tmp/evtest.log"
    listenLog = "/tmp/listen.log"

    # the daemon was restarted above, so (re)locate its fresh output device
    # (udev takes a moment to register it)
    sysfsName = machine.wait_until_succeeds(
      "grep -l 'keyd virtual keyboard' /sys/class/input/event*/device/name | head -1"
    ).strip()
    evdev = "/dev/input/" + sysfsName.split("/")[-3]
    print(f"keyd output device: {evdev}")

    # record its output from the start
    machine.execute(f"nohup stdbuf -oL ${pkgs.evtest}/bin/evtest {evdev} > {evtestLog} 2>&1 &")
    # ...and track layer state changes of the daemon
    machine.execute(f"nohup ${pkgs.keyd}/bin/keyd listen > {listenLog} 2>&1 &")
    machine.sleep(2)

    # hold a + tap l (overloadt timeout is 130ms; the hold outlasts it)
    def holdAandTapL(holdTime):
        press(30, 1)  # KEY_A down
        machine.sleep(holdTime)
        press(38, 1)  # KEY_L down (quick: below the 130ms overload timeout)
        press(38, 0)  # KEY_L up
        machine.sleep(1)
        press(30, 0)  # KEY_A up
        machine.sleep(1)

    # --- phase 1: remaps active -> holding a acts as meta -------------
    holdAandTapL(1)

    # --- f21 press: a/s/d become plain letters ------------------------
    tapF21()
    machine.wait_until_succeeds(f"grep -q '^+lhsOff' {listenLog}")

    # --- phase 2: lhsOff layer occludes the remaps --------------------
    holdAandTapL(1)

    # --- f21 press again: remaps restored ------------------------------
    tapF21()
    machine.wait_until_succeeds(f"grep -q '^-lhsOff' {listenLog}")

    # --- phase 3: holding a acts as meta again -------------------------
    holdAandTapL(1)
    machine.sleep(1)

    # exactly one toggle-on and one toggle-off layer state change
    machine.succeed(f"test $(grep -c '^+lhsOff' {listenLog}) -eq 1")
    machine.succeed(f"test $(grep -c '^-lhsOff' {listenLog}) -eq 1")

    # KEY_A is emitted exactly once: only while lhsOff is active (holding a
    # acts as meta in phases 1 and 3, so no KEY_A there)
    machine.succeed(f"test $(grep -c 'code 30 (KEY_A), value 1' {evtestLog}) -eq 1")
    machine.succeed(f"test $(grep -c 'code 30 (KEY_A), value 0' {evtestLog}) -eq 1")

    # KEY_LEFTMETA is synthesized exactly twice (once per remapped hold):
    # no meta while lhsOff is active
    machine.succeed(f"test $(grep -c 'code 125 (KEY_LEFTMETA), value 1' {evtestLog}) -eq 2")
    machine.succeed(f"test $(grep -c 'code 125 (KEY_LEFTMETA), value 0' {evtestLog}) -eq 2")

    # the l taps came through in all three phases
    machine.succeed(f"test $(grep -c 'code 38 (KEY_L), value 1' {evtestLog}) -eq 3")
    machine.succeed(f"test $(grep -c 'code 38 (KEY_L), value 0' {evtestLog}) -eq 3")
  '';
}