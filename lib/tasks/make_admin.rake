namespace :admin do
  desc "Make a user an admin by email"
  task :create, [:email] => :environment do |t, args|
    email = args[:email]
    
    if email.blank?
      puts "Please provide an email. Usage: rails admin:create[user@example.com]"
      next
    end
    
    user = User.find_by(email: email)
    
    if user
      user.update(admin: true)
      puts "User #{email} is now an admin."
    else
      puts "User with email #{email} not found."
    end
  end
  
  desc "List all admin users"
  task list: :environment do
    admin_users = User.where(admin: true)
    
    if admin_users.any?
      puts "Admin users:"
      admin_users.each do |user|
        puts "- #{user.email}"
      end
    else
      puts "No admin users found."
    end
  end
end
