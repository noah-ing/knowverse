FactoryBot.define do
  factory :billing_event do
    association :organization
    sequence(:stripe_event_id) { |n| "evt_test_#{n}" }
    event_type { "customer.subscription.created" }
    data { { object: { id: "sub_test", status: "active" } } }
    processed_at { nil }
    status { "pending" }
    error_message { nil }

    trait :processed do
      status { "processed" }
      processed_at { Time.current }
    end

    trait :failed do
      status { "failed" }
      error_message { "Test error message" }
    end

    trait :subscription_updated do
      event_type { "customer.subscription.updated" }
    end

    trait :payment_succeeded do
      event_type { "invoice.payment_succeeded" }
      data { { object: { id: "in_test", amount_paid: 4900 } } }
    end

    trait :payment_failed do
      event_type { "invoice.payment_failed" }
      data { { object: { id: "in_test", amount_due: 4900 } } }
    end
  end
end
