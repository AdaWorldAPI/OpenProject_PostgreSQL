# frozen_string_literal: true

# Rake task: Reset the admin user password from environment variables.
#
# Fixes the Railway.com first-login problem where:
#   1. admin/admin doesn't work (env var set a different password during seed)
#   2. Account is locked from failed login attempts
#   3. force_password_change blocks login even with correct password
#
# Usage:
#   rake admin:reset_password                    # Uses OPENPROJECT_SEED__ADMIN__USER__PASSWORD
#   rake admin:reset_password[mysecretpassword]  # Uses explicit password
#   rake admin:unlock                            # Just unlock, don't change password
#   rake admin:status                            # Show admin account state
#
# Environment variables:
#   OPENPROJECT_SEED__ADMIN__USER__PASSWORD       - Password to set (default: "admin")
#   OPENPROJECT_SEED__ADMIN__USER__PASSWORD__RESET - "true" to force change on next login

namespace :admin do
  desc "Reset admin password from ENV or argument, unlock account, clear force_password_change"
  task :reset_password, [:password] => :environment do |_t, args|
    admin = User.find_by(login: "admin")

    unless admin
      puts "[admin:reset_password] ERROR: No user with login 'admin' found."
      puts "  Run 'rake db:seed' first to create the admin user."
      exit 1
    end

    password = args[:password] ||
               ENV["OPENPROJECT_SEED__ADMIN__USER__PASSWORD"] ||
               ENV["OPENPROJECT_SEED_ADMIN_USER_PASSWORD"] ||
               "admin"

    force_reset = ENV.fetch("OPENPROJECT_SEED__ADMIN__USER__PASSWORD__RESET",
                            ENV.fetch("OPENPROJECT_SEED_ADMIN_USER_PASSWORD_RESET", "false"))
    force_change = %w[true 1 yes].include?(force_reset.to_s.downcase)

    # Reset password
    admin.password = password
    admin.password_confirmation = password

    # Unlock account (clear brute force lockout)
    admin.failed_login_count = 0
    admin.last_failed_login_on = nil

    # Set force_password_change based on env
    admin.force_password_change = force_change

    # Ensure active
    admin.activate if admin.respond_to?(:activate) && !admin.active?

    if admin.save
      puts "[admin:reset_password] Admin password reset successfully."
      puts "  Login: admin"
      puts "  Password: #{password == 'admin' ? 'admin' : '(from env var)'}"
      puts "  Force password change: #{force_change}"
      puts "  Account locked: no (cleared)"
      puts "  Status: #{admin.status}"
    else
      puts "[admin:reset_password] ERROR: Failed to save admin user."
      admin.errors.full_messages.each { |msg| puts "  - #{msg}" }
      exit 1
    end
  end

  desc "Unlock admin account (clear failed login count, no password change)"
  task unlock: :environment do
    admin = User.find_by(login: "admin")

    unless admin
      puts "[admin:unlock] ERROR: No user with login 'admin' found."
      exit 1
    end

    admin.update_columns(
      failed_login_count: 0,
      last_failed_login_on: nil
    )

    puts "[admin:unlock] Admin account unlocked."
    puts "  Failed login count: 0"
    puts "  Last failed login: cleared"
  end

  desc "Show admin account status (locked, password change required, etc.)"
  task status: :environment do
    admin = User.find_by(login: "admin")

    unless admin
      puts "[admin:status] No user with login 'admin' found."
      exit 0
    end

    blocked = admin.respond_to?(:failed_too_many_recent_login_attempts?) &&
              admin.failed_too_many_recent_login_attempts?

    puts "[admin:status]"
    puts "  Login:                 #{admin.login}"
    puts "  Email:                 #{admin.mail}"
    puts "  Status:                #{admin.status}"
    puts "  Active:                #{admin.active?}"
    puts "  Admin:                 #{admin.admin?}"
    puts "  Force password change: #{admin.force_password_change}"
    puts "  Password expired:      #{admin.respond_to?(:password_expired?) ? admin.password_expired? : 'N/A'}"
    puts "  Failed login count:    #{admin.failed_login_count}"
    puts "  Last failed login:     #{admin.last_failed_login_on || 'never'}"
    puts "  Brute force blocked:   #{blocked}"
    puts "  Has password hash:     #{admin.respond_to?(:current_password) ? !admin.current_password.nil? : 'N/A'}"
    puts ""
    puts "  ENV password set:      #{ENV.key?('OPENPROJECT_SEED__ADMIN__USER__PASSWORD') || ENV.key?('OPENPROJECT_SEED_ADMIN_USER_PASSWORD')}"
    puts "  ENV force reset:       #{ENV.fetch('OPENPROJECT_SEED__ADMIN__USER__PASSWORD__RESET', ENV.fetch('OPENPROJECT_SEED_ADMIN_USER_PASSWORD_RESET', '(not set)'))}"
  end
end
