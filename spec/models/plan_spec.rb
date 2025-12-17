require 'rails_helper'

RSpec.describe Plan, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:stripe_price_id) }
    it { should validate_uniqueness_of(:stripe_price_id) }
    it { should validate_presence_of(:amount) }
    it { should validate_numericality_of(:amount).is_greater_than_or_equal_to(0) }
    it { should validate_presence_of(:interval) }
    it { should validate_inclusion_of(:interval).in_array(%w[month year]) }
  end

  describe 'scopes' do
    before do
      create(:plan, active: true)
      create(:plan, active: false)
    end

    describe '.active' do
      it 'returns only active plans' do
        expect(Plan.active.count).to eq(1)
        expect(Plan.active.first.active).to be_truthy
      end
    end
  end

  describe 'instance methods' do
    describe '#formatted_price' do
      it 'returns "Free" for zero amount' do
        plan = build(:plan, amount: 0)
        expect(plan.formatted_price).to eq('Free')
      end

      it 'formats monthly prices correctly' do
        plan = build(:plan, amount: 999, interval: 'month')
        expect(plan.formatted_price).to eq('$9.99/month')
      end

      it 'formats yearly prices correctly' do
        plan = build(:plan, amount: 9900, interval: 'year')
        expect(plan.formatted_price).to eq('$99.00/year')
      end
    end

    describe '#feature_list' do
      it 'returns features array if present' do
        features = ['Feature 1', 'Feature 2']
        plan = build(:plan, features: features)
        expect(plan.feature_list).to eq(features)
      end

      it 'returns empty array if features is nil' do
        plan = build(:plan, features: nil)
        expect(plan.feature_list).to eq([])
      end
    end
  end
end
