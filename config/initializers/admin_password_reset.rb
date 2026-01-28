# frozen_string_literal: true

# Railway.com auto-reset: On every boot, if OPENPROJECT_SEED__ADMIN__USER__PASSWORD__RESET
# is "true", reset the admin password to the value from OPENPROJECT_SEED__ADMIN__USER__PASSWORD.
#
# This runs as a Rails initializer so it executes on every deploy/restart,
# not just during the initial seed. This is what makes Railway redeploys work:
#   - Set OPENPROJECT_SEED__ADMIN__USER__PASSWORD=YourSecurePassword
#   - Set OPENPROJECT_SEED__ADMIN__USER__PASSWORD__RESET=true
#   - Redeploy → admin password is force-reset to env var value
#   - Login with admin / YourSecurePassword
#
# Once you've logged in and changed the password manually, set
# OPENPROJECT_SEED__ADMIN__USER__PASSWORD__RESET=false to stop resetting on boot.

Rails.application.config.after_initialize do
  next unless ActiveRecord::Base.connection.table_exists?(:users)

  reset_flag = ENV.fetch("OPENPROJECT_SEED__ADMIN__USER__PASSWORD__RESET",
                         ENV.fetch("OPENPROJECT_SEED_ADMIN_USER_PASSWORD_RESET", "false"))
  should_reset = %w[true 1 yes].include?(reset_flag.to_s.strip.downcase)

  next unless should_reset

  admin = User.find_by(login: "admin")
  next unless admin

  password = ENV.fetch("OPENPROJECT_SEED__ADMIN__USER__PASSWORD",
                       ENV.fetch("OPENPROJECT_SEED_ADMIN_USER_PASSWORD", "admin"))

  admin.password = password
  admin.password_confirmation = password
  admin.failed_login_count = 0
  admin.last_failed_login_on = nil
  admin.force_password_change = false

  if admin.save
    Rails.logger.info("[admin_password_reset] Admin password reset from environment variable on boot.")
  else
    Rails.logger.error("[admin_password_reset] Failed to reset admin password: #{admin.errors.full_messages.join(', ')}")
  end
rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid => e
  # Database not yet created (first deploy before db:create/migrate)
  Rails.logger.debug("[admin_password_reset] Skipped: #{e.message}")
end
