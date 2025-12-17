FactoryBot.define do
  factory :organization_user do
    organization { nil }
    user { nil }
    role { "MyString" }
    invitation_token { "MyString" }
    invitation_accepted_at { "2025-04-02 12:01:04" }
  end
end
