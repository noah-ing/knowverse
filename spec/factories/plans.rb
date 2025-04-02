FactoryBot.define do
  factory :plan do
    name { 'Basic Plan' }
    stripe_price_id { "price_#{SecureRandom.alphanumeric(14)}" }
    amount { 999 } # $9.99
    interval { 'month' }
    features { ['Feature 1', 'Feature 2', 'Feature 3'] }
    active { true }
    
    trait :basic do
      name { 'Basic' }
      amount { 999 } # $9.99
      features { ['10 Widgets', 'Basic Support', 'Standard Reports'] }
    end
    
    trait :plus do
      name { 'Plus' }
      amount { 1999 } # $19.99
      features { ['25 Widgets', 'Priority Support', 'Advanced Reports', 'API Access'] }
    end
    
    trait :premium do
      name { 'Premium' }
      amount { 4999 } # $49.99
      features { ['Unlimited Widgets', 'Premium Support', 'Custom Reports', 'API Access', 'White Labeling'] }
    end
    
    trait :enterprise do
      name { 'Enterprise' }
      amount { 9999 } # $99.99
      features { ['Unlimited Everything', 'Dedicated Support', 'Custom Development', 'API Access', 'White Labeling', 'SLA Guarantee'] }
    end
    
    trait :yearly do
      interval { 'year' }
      # Usually yearly plans have a discount compared to monthly
      after(:build) do |plan|
        plan.amount = (plan.amount * 10) # 2 months free
      end
    end
    
    trait :inactive do
      active { false }
    end
  end
end
