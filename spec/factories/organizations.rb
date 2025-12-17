FactoryBot.define do
  factory :organization do
    sequence(:name) { |n| "Organization #{n}" }
    sequence(:slug) { |n| "org-#{n}" }
    settings { { search_provider: 'hybrid', embedding_model: 'all-mpnet-base-v2' } }
    active { true }

    trait :inactive do
      active { false }
    end

    trait :with_custom_settings do
      settings do
        {
          search_provider: 'semantic',
          embedding_model: 'all-MiniLM-L6-v2',
          domain_detection_enabled: true,
          max_results: 20
        }
      end
    end

    trait :with_documents do
      transient do
        document_count { 5 }
      end

      after(:create) do |organization, evaluator|
        create_list(:document, evaluator.document_count, organization: organization)
      end
    end
  end
end
