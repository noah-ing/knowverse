FactoryBot.define do
  factory :conversation_message do
    association :conversation_session
    role { "user" }
    content { Faker::Lorem.paragraph }
    token_count { content.split.size * 1.3 } # Approximate tokens
    metadata { { timestamp: Time.current.iso8601 } }

    trait :user do
      role { "user" }
      content { "What are the key findings in the quarterly report?" }
    end

    trait :assistant do
      role { "assistant" }
      content { "Based on the quarterly report, the key findings include..." }
      metadata do
        {
          timestamp: Time.current.iso8601,
          model: 'gpt-4',
          sources: [{ document_id: 1, relevance: 0.92 }]
        }
      end
    end

    trait :system do
      role { "system" }
      content { "You are a helpful assistant that answers questions about documents." }
    end

    trait :with_sources do
      transient do
        source_count { 3 }
      end

      metadata do
        {
          timestamp: Time.current.iso8601,
          sources: Array.new(source_count) do |i|
            { document_id: i + 1, relevance: rand(0.7..0.99).round(2) }
          end
        }
      end
    end
  end
end
