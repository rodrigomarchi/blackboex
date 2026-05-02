# Onboarding Smoke Test (manual)

Verify the first-run flow on a clean database before tagging a release.

## Steps

1. **Reset DB**:
   ```
   make db.reset
   ```
2. **Start server**:
   ```
   make server
   ```
3. **First-run redirect**: open `http://localhost:4000`. You should be redirected to `/setup`.
4. **Wizard completion**: complete each step (Instance → Admin → Organization → Review). After submit you should land on `/orgs/<slug>/projects/<slug>` logged in as the admin.
5. **Setup is gone**: navigate to `/setup`. You should see HTTP 404 (or no-route).
6. **Registration is gone**: navigate to `/users/register`. You should see 404.
7. **Invite flow**: from the org members page, click **Invite member**, enter an email + role, submit. Open the dev mailbox at `/dev/mailbox` and grab the link. Open the link in a private/incognito window. You should be able to set a password (if new user) or click to join (if existing). After accept, you should be logged in and inside the invited org.
8. **API surface intact**: confirm `/api/...`, `/p/...`, `/webhook/...` continue to respond on a fresh DB before setup completes (no redirect to `/setup`).

## Failure modes

- Stuck redirect loop on `/setup` → check the `instance_settings` row was inserted in the transaction (`SELECT * FROM instance_settings;`).
- 500 on submit → check the LiveView error log; common cause is `Organizations.create_organization/2` returning a different shape than expected.
- Magic link missing in `/dev/mailbox` → check `config/dev.exs` mailer adapter is `Swoosh.Adapters.Local`.
