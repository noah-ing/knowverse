FactoryBot.define do
  factory :document do
    association :organization
    sequence(:title) { |n| "Document #{n}" }
    description { "A test document for search and retrieval" }
    file_type { "text/plain" }
    status { "active" }
    content { Faker::Lorem.paragraphs(number: 5).join("\n\n") }
    embedding_status { "pending" }
    word_count { content&.split&.size || 0 }
    metadata { { source: 'test', created_at: Time.current.iso8601 } }

    trait :pdf do
      file_type { "application/pdf" }
      title { "Report.pdf" }
    end

    trait :excel do
      file_type { "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" }
      title { "Data.xlsx" }
    end

    trait :docx do
      file_type { "application/vnd.openxmlformats-officedocument.wordprocessingml.document" }
      title { "Document.docx" }
    end

    trait :embedded do
      embedding_status { "completed" }
      after(:create) do |document|
        create(:vector_embedding, document: document)
      end
    end

    trait :failed_embedding do
      embedding_status { "failed" }
    end

    trait :processing do
      embedding_status { "processing" }
    end

    trait :archived do
      status { "archived" }
    end

    trait :with_content do
      transient do
        custom_content { nil }
      end

      content do
        custom_content || <<~CONTENT
          Machine Learning and Artificial Intelligence

          This document discusses the fundamentals of machine learning,
          including supervised and unsupervised learning techniques.

          Neural networks have revolutionized the field, enabling breakthrough
          applications in computer vision, natural language processing, and
          autonomous systems.
        CONTENT
      end
    end
  end
end
