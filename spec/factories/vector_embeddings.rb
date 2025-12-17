FactoryBot.define do
  factory :vector_embedding do
    association :document
    model_name { "all-mpnet-base-v2" }
    dimension { 768 }
    status { "active" }
    embedding { Array.new(768) { rand(-1.0..1.0) } }
    metadata { { generated_at: Time.current.iso8601, model_version: "1.0" } }

    trait :mini_lm do
      model_name { "all-MiniLM-L6-v2" }
      dimension { 384 }
      embedding { Array.new(384) { rand(-1.0..1.0) } }
    end

    trait :bge_large do
      model_name { "bge-large-en-v1.5" }
      dimension { 1024 }
      embedding { Array.new(1024) { rand(-1.0..1.0) } }
    end

    trait :inactive do
      status { "inactive" }
    end

    trait :with_domain do
      transient do
        domain { "technology" }
      end

      metadata do
        {
          generated_at: Time.current.iso8601,
          domain: domain,
          domain_confidence: 0.85
        }
      end
    end
  end
end
