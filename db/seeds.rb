# This file contains all the record creation needed to seed the database with its default values.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Load subscription plans
require_relative 'seeds/plans'

# Create admin user if none exists
admin_email = ENV['ADMIN_EMAIL'] || 'admin@example.com'
admin_password = ENV['ADMIN_PASSWORD'] || 'password'

unless User.exists?(email: admin_email)
  admin = User.create!(
    email: admin_email,
    password: admin_password,
    admin: true
  )
  puts "Created admin user: #{admin_email}"
end
