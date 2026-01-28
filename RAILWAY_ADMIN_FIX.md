# Fix: Admin Login on Railway.com

## The Problem

After deploying OpenProject on Railway, `admin / admin` shows:

> Benutzer oder Kennwort ist ungültig oder der Account wurde wegen
> mehrfacher Falscheingabe temporär gesperrt

Three things cause this:

1. **Env var password**: If `OPENPROJECT_SEED__ADMIN__USER__PASSWORD` was set during
   initial seed, the password is NOT `admin` — it's whatever the env var says.
   But that only runs once during `db:seed`.

2. **Force password change**: Production default sets `force_password_change = true`.
   Even with the correct password, OpenProject redirects to a password change form
   that may fail or confuse.

3. **Brute force lockout**: After 20 failed attempts with `admin/admin`, the account
   is locked for 30 minutes. The German error message is the lockout message.

## The Fix

### Railway Environment Variables

Set these in your Railway service:

```
OPENPROJECT_SEED__ADMIN__USER__PASSWORD=YourSecurePassword123!
OPENPROJECT_SEED__ADMIN__USER__PASSWORD__RESET=true
```

### What Happens on Deploy

The initializer `config/initializers/admin_password_reset.rb` runs on every boot.
When `OPENPROJECT_SEED__ADMIN__USER__PASSWORD__RESET=true`:

1. Finds the `admin` user
2. Sets password to `OPENPROJECT_SEED__ADMIN__USER__PASSWORD` value
3. Clears `failed_login_count` (unlocks account)
4. Sets `force_password_change = false` (no redirect)
5. Logs success

### Login

After deploy, login with:
- Username: `admin`
- Password: whatever you set in `OPENPROJECT_SEED__ADMIN__USER__PASSWORD`

### After First Login

Once you're in, set:

```
OPENPROJECT_SEED__ADMIN__USER__PASSWORD__RESET=false
```

This stops the password from being overwritten on every restart.

## Manual Rake Tasks

If you need to fix it manually via Railway console:

```bash
# Reset password to env var value (or 'admin' if not set)
rake admin:reset_password

# Reset to a specific password
rake admin:reset_password[MyPassword123]

# Just unlock the account (don't change password)
rake admin:unlock

# Check account status
rake admin:status
```

## How It Works

```
Railway Deploy
  |
  +-> Rails boots
  |     |
  |     +-> config/initializers/admin_password_reset.rb
  |           |
  |           +-> RESET=true? ──yes──> Reset password + unlock + save
  |           |
  |           +-> RESET=false? ─────> Skip (do nothing)
  |
  +-> User logs in as admin / EnvVarPassword
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| "Kennwort ungültig" | Wrong password | Check `OPENPROJECT_SEED__ADMIN__USER__PASSWORD` value |
| "temporär gesperrt" | Brute force lock (20 attempts) | Set `RESET=true` and redeploy, or `rake admin:unlock` |
| Redirects to password change | `force_password_change=true` | Set `RESET=true` and redeploy (clears the flag) |
| No admin user exists | Seed never ran | `rake db:seed` |
