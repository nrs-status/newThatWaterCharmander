
```sh
# build the VM (this also builds the host-side viewer/ssh wrappers)
nixos-rebuild build-vm --flake .#wranHearst
# or
nix build .#nixosConfigurations.wranHearst.config.system.build.vm

# run it (creates ./wranHearst.qcow2, loopback-only SPICE + VNC + SSH)
./result/bin/run-wranHearst-vm

# watch the VM's compositor at any time
wranHearst-vm-view                      # remote-viewer, spice://127.0.0.1:5901
# or any VNC client: remote-viewer vnc://127.0.0.1:5902

# drive/test the compositor from an agent on the host
wranHearst-vm-ssh 'swaymsg -t get_tree | jq .'
wranHearst-vm-ssh 'grim /tmp/shot.png'
wranHearst-vm-ssh 'cat /tmp/sway.log'   # sway's stderr, for crash debugging
```

The `wranHearst-vm-*` wrappers are installed by `environment.systemPackages`
in the host configuration, so they appear after the next
`nixos-rebuild switch`; until then they can be run from their store paths.
