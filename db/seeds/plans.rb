# Create subscription plans
# Pricing: Free $0, Starter $49, Growth $149, Business $399
# Enterprise is contact sales (not seeded)

puts "Seeding subscription plans..."

plans_data = [
  {
    name: 'Free',
    stripe_price_id: ENV.fetch('STRIPE_FREE_PRICE_ID', 'price_free_monthly'),
    amount: 0,
    interval: 'month',
    max_documents: 50,
    max_queries_per_month: 500,
    max_team_members: 3,
    advanced_search: false,
    api_access: false,
    trial_days: 0,
    description: 'Perfect for trying KnowVerse',
    display_order: 0,
    features: [
      '50 documents',
      '500 queries/month',
      'Up to 3 team members',
      'Basic semantic search',
      '1 connector'
    ],
    active: true
  },
  {
    name: 'Starter',
    stripe_price_id: ENV.fetch('STRIPE_STARTER_PRICE_ID', 'price_starter_monthly'),
    amount: 4900, # $49.00
    interval: 'month',
    max_documents: 500,
    max_queries_per_month: 2500,
    max_team_members: 10,
    advanced_search: false,
    api_access: false,
    trial_days: 14,
    description: 'For small teams getting started',
    display_order: 1,
    features: [
      '500 documents',
      '2,500 queries/month',
      'Up to 10 team members',
      'Full RAG capabilities',
      'Hybrid search',
      'All connectors',
      'Email support'
    ],
    active: true
  },
  {
    name: 'Growth',
    stripe_price_id: ENV.fetch('STRIPE_GROWTH_PRICE_ID', 'price_growth_monthly'),
    amount: 14900, # $149.00
    interval: 'month',
    max_documents: 2500,
    max_queries_per_month: 15000,
    max_team_members: 25,
    advanced_search: true,
    api_access: true,
    trial_days: 14,
    description: 'For growing teams with advanced needs',
    display_order: 2,
    features: [
      '2,500 documents',
      '15,000 queries/month',
      'Up to 25 team members',
      'API access',
      'Advanced analytics',
      'Priority support',
      'Custom embeddings'
    ],
    active: true
  },
  {
    name: 'Business',
    stripe_price_id: ENV.fetch('STRIPE_BUSINESS_PRICE_ID', 'price_business_monthly'),
    amount: 39900, # $399.00
    interval: 'month',
    max_documents: 10000,
    max_queries_per_month: 50000,
    max_team_members: 100,
    advanced_search: true,
    api_access: true,
    trial_days: 14,
    description: 'For large teams with enterprise needs',
    display_order: 3,
    features: [
      '10,000 documents',
      '50,000 queries/month',
      'Up to 100 team members',
      'SSO/SAML',
      'Audit logs',
      'Priority support',
      'Dedicated success manager'
    ],
    active: true
  }
]

plans_data.each do |plan_attrs|
  plan = Plan.find_or_initialize_by(name: plan_attrs[:name])
  plan.assign_attributes(plan_attrs)
  plan.save!
  puts "  - #{plan.name}: #{plan.formatted_price}"
end

puts "Created/updated #{Plan.count} subscription plans"
