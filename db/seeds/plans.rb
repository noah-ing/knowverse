# Create subscription plans

# Clear existing plans
Plan.destroy_all

# Basic (Free) Plan
Plan.create!(
  name: 'Basic',
  stripe_price_id: 'price_basic_free',
  amount: 0,
  interval: 'month',
  features: [
    'Core features',
    'Limited usage',
    'Email support'
  ],
  active: true
)

# Plus Plan
Plan.create!(
  name: 'Plus',
  stripe_price_id: 'price_plus_monthly',
  amount: 999, # $9.99
  interval: 'month',
  features: [
    'All Basic features',
    'Increased usage limits',
    'Priority email support',
    'Advanced analytics'
  ],
  active: true
)

# Premium Plan
Plan.create!(
  name: 'Premium',
  stripe_price_id: 'price_premium_monthly',
  amount: 1999, # $19.99
  interval: 'month',
  features: [
    'All Plus features',
    'Unlimited usage',
    'Priority support',
    'Advanced analytics',
    'Custom integrations'
  ],
  active: true
)

# Enterprise Plan
Plan.create!(
  name: 'Enterprise',
  stripe_price_id: 'price_enterprise_monthly',
  amount: 9999, # $99.99
  interval: 'month',
  features: [
    'All Premium features',
    'Dedicated support',
    'Custom development',
    'SLA guarantees',
    'Onboarding assistance',
    'Team training'
  ],
  active: true
)

puts "Created #{Plan.count} subscription plans"
