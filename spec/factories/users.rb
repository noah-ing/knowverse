FactoryBot.define do
  factory :user do
    email { Faker::Internet.unique.email }
    password { 'password123' }
    login_token { nil }
    login_token_sent_at { nil }
    name { Faker::Name.name }
    admin { false }
    notification_preferences { { email_updates: true, marketing: false } }
    
    # Stripe attributes
    stripe_customer_id { nil }
    stripe_subscription_id { nil }
    subscription_status { nil }
    trial_ends_at { nil }
    card_brand { nil }
    card_last4 { nil }
    card_exp_month { nil }
    card_exp_year { nil }
    
    trait :with_login_token do
      login_token { SecureRandom.uuid }
      login_token_sent_at { Time.current }
    end
    
    trait :admin do
      admin { true }
    end
    
    trait :with_subscription do
      stripe_customer_id { "cus_#{SecureRandom.alphanumeric(14)}" }
      stripe_subscription_id { "sub_#{SecureRandom.alphanumeric(14)}" }
      subscription_status { 'active' }
      card_brand { ['visa', 'mastercard', 'amex'].sample }
      card_last4 { Faker::Number.number(digits: 4).to_s }
      card_exp_month { rand(1..12) }
      card_exp_year { Time.current.year + rand(1..5) }
    end
    
    trait :trialing do
      stripe_customer_id { "cus_#{SecureRandom.alphanumeric(14)}" }
      stripe_subscription_id { "sub_#{SecureRandom.alphanumeric(14)}" }
      subscription_status { 'trialing' }
      trial_ends_at { 14.days.from_now }
    end
    
    trait :past_due do
      stripe_customer_id { "cus_#{SecureRandom.alphanumeric(14)}" }
      stripe_subscription_id { "sub_#{SecureRandom.alphanumeric(14)}" }
      subscription_status { 'past_due' }
    end
    
    trait :canceled do
      stripe_customer_id { "cus_#{SecureRandom.alphanumeric(14)}" }
      stripe_subscription_id { "sub_#{SecureRandom.alphanumeric(14)}" }
      subscription_status { 'canceled' }
    end
    
    trait :with_avatar do
      after(:build) do |user|
        file_path = Rails.root.join('spec', 'fixtures', 'files', 'avatar.jpg')
        
        # Create the directory if it doesn't exist
        FileUtils.mkdir_p(File.dirname(file_path)) unless File.exist?(File.dirname(file_path))
        
        # Create a sample image file if it doesn't exist
        unless File.exist?(file_path)
          File.open(file_path, 'wb') do |f|
            f.write('fake image content')
          end
        end
        
        user.avatar.attach(
          io: File.open(file_path),
          filename: 'avatar.jpg',
          content_type: 'image/jpeg'
        )
      end
    end
  end
end
