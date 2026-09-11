{
  system.stateVersion = "26.11";

  # root password is declared here rather than set imperatively (e.g. via
  # chpasswd) because the impermanence rollback wipes the root subvolume on
  # every boot, resetting /etc/shadow to the pristine state
  users.users.root.hashedPassword = "$6$xyx9wiTbAipINj/9$8YR9WsLY.RoYhV7cVufX9vvxzp.dc9eoHSVAb.55xoxabKb3JnIg8DwtUeNK36sZlR5ngL.HT7TFCDP0HF7EU.";
}
