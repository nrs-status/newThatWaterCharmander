# shared credentials for the arunman run-tracking stream (see
# templeArtemisEphesus/arunman/SPEC.md in the frontArmToPlane flake):
# `arunman' records every pi microvm run in the `run' table of this
# database on wranHearst's postgresql server, so both the server side
# (./default.nix, which provisions the role with this password) and the
# client side (the `databaseUrl' of arunman's TOML config, which connects
# with this password) need them.
#
# NOTE: the password lives in plain text in the repository (and therefore in
# the nix store, world-readable): acceptable for this lab setup; the postgres
# role is restricted to the arunman database (DML on the `run' table only),
# and the pg_hba rules only accept scram-sha-256 from private LAN ranges.
{
  arunmanDatabase = "arunman";
  arunmanUser = "arunman";
  arunmanPassword = "kq9tW3vZ7uXm2Ry8nLb5Jc4h";
}
