FactoryBot.define do
  factory :conversation_session do
    association :organization
    association :user
    sequence(:session_id) { |n| SecureRandom.uuid }
    title { "Conversation about #{Faker::Lorem.words(number: 3).join(' ')}" }
    status { "active" }
    context { { domain: 'general', language: 'en' } }
    metadata { { created_via: 'api', client: 'web' } }

    trait :with_messages do
      transient do
        message_count { 4 }
      end

      after(:create) do |session, evaluator|
        evaluator.message_count.times do |i|
          role = i.even? ? 'user' : 'assistant'
          create(:conversation_message, conversation_session: session, role: role)
        end
      end
    end

    trait :completed do
      status { "completed" }
    end

    trait :archived do
      status { "archived" }
    end
  end
end
