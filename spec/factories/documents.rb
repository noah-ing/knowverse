FactoryBot.define do
  factory :document do
    title { "MyString" }
    description { "MyText" }
    file_type { "MyString" }
    status { "MyString" }
    content { "MyText" }
    embedding_status { "MyString" }
    organization { nil }
    word_count { 1 }
    metadata { "" }
  end
end
