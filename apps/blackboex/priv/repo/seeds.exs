# This file is intentionally a no-op for the open-source release.
#
# A first-run setup wizard at http://localhost:4000/setup creates the
# initial platform admin user, organization, and project when the
# database is empty. Run `make setup` to bring up the database, then
# open the app in a browser to complete the wizard.
#
# Optionally, set BLACKBOEX_DEMO=true to seed example data. Currently
# the demo seed is unimplemented; add it here if/when needed.

if System.get_env("BLACKBOEX_DEMO") == "true" do
  IO.puts("Demo seed requested but not implemented yet — skipping.")
end

:ok
