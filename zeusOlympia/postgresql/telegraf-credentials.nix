# shared credentials for the telegraf telemetry stream (see ../telegraf):
# the agent hosts augtibcalcla and lanchamarcou stream metrics into this
# database on wranHearst's postgresql server, so both the server side
# (./default.nix, which provisions the role with this password) and the client
# side (../telegraf, which connects with this password) need them.
#
# NOTE: the password lives in plain text in the repository (and therefore in
# the nix store, world-readable): acceptable for this lab setup; the postgres
# role is restricted to the telemetry database, insert-only, and the pg_hba
# rules only accept scram-sha-256 from private LAN ranges.
{
  telegrafDatabase = "telemetry";
  telegrafUser = "telegraf";
  telegrafPassword = "2WBzdNnkzV944Ek8jAJAvKSPPxBhlbQx";
}
