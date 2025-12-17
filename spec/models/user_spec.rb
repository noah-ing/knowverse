require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'associations' do
    it { should have_one_attached(:avatar) }
  end

  describe 'validations' do
    it { should validate_inclusion_of(:subscription_status).in_array(User::SUBSCRIPTION_STATUSES).allow_nil }
    it { should validate_length_of(:name).is_at_most(100).allow_blank }
  end

  describe 'instance methods' do
    describe '#admin?' do
      it 'returns true if user is an admin' do
        user = build(:user, admin: true)
        expect(user.admin?).to be_truthy
      end

      it 'returns false if user is not an admin' do
        user = build(:user, admin: false)
        expect(user.admin?).to be_falsey
      end
    end

    describe 'subscription status helpers' do
      let(:active_user) { build(:user, :with_subscription) }
      let(:trialing_user) { build(:user, :trialing) }
      let(:past_due_user) { build(:user, :past_due) }
      let(:canceled_user) { build(:user, :canceled) }
      let(:no_subscription_user) { build(:user) }

      describe '#trialing?' do
        it 'returns true if subscription is trialing and trial end date is in the future' do
          expect(trialing_user.trialing?).to be_truthy
        end

        it 'returns false if subscription is not trialing' do
          expect(active_user.trialing?).to be_falsey
        end
      end

      describe '#active_subscription?' do
        it 'returns true if subscription is active' do
          expect(active_user.active_subscription?).to be_truthy
        end

        it 'returns false if subscription is not active' do
          expect(past_due_user.active_subscription?).to be_falsey
        end
      end

      describe '#past_due?' do
        it 'returns true if subscription is past_due' do
          expect(past_due_user.past_due?).to be_truthy
        end

        it 'returns false if subscription is not past_due' do
          expect(active_user.past_due?).to be_falsey
        end
      end

      describe '#canceled?' do
        it 'returns true if subscription is canceled' do
          expect(canceled_user.canceled?).to be_truthy
        end

        it 'returns false if subscription is not canceled' do
          expect(active_user.canceled?).to be_falsey
        end
      end

      describe '#subscribed?' do
        it 'returns true if subscription is active' do
          expect(active_user.subscribed?).to be_truthy
        end

        it 'returns true if subscription is trialing' do
          expect(trialing_user.subscribed?).to be_truthy
        end

        it 'returns false if subscription is past_due or canceled' do
          expect(past_due_user.subscribed?).to be_falsey
          expect(canceled_user.subscribed?).to be_falsey
        end
      end
    end

    describe '#card_info' do
      it 'returns formatted card info if card details are present' do
        user = build(:user, card_brand: 'visa', card_last4: '4242')
        expect(user.card_info).to eq('Visa ending in 4242')
      end

      it 'returns "No payment method" if card details are missing' do
        user = build(:user, card_brand: nil, card_last4: nil)
        expect(user.card_info).to eq('No payment method')
      end
    end

    describe '#card_expiration' do
      it 'returns formatted expiration date if details are present' do
        user = build(:user, card_exp_month: 12, card_exp_year: 2025)
        expect(user.card_expiration).to eq('12/2025')
      end

      it 'returns empty string if card expiration details are missing' do
        user = build(:user, card_exp_month: nil, card_exp_year: nil)
        expect(user.card_expiration).to eq('')
      end
    end

    describe '#stripe_customer' do
      it 'retrieves existing customer if stripe_customer_id is present' do
        user = build(:user, stripe_customer_id: 'cus_123')
        stub_stripe_customer_retrieve
        user.stripe_customer
        expect(Stripe::Customer).to have_received(:retrieve)
      end

      it 'creates new customer if stripe_customer_id is nil' do
        user = build(:user, stripe_customer_id: nil)
        stub_stripe_customer_create
        user.stripe_customer
        expect(Stripe::Customer).to have_received(:create)
      end
    end

    describe '#update_card_details' do
      it 'updates card details from Stripe payment method' do
        user = build(:user)
        payment_method = double(
          card: double(
            brand: 'mastercard',
            last4: '9876',
            exp_month: 11,
            exp_year: 2026
          )
        )

        user.update_card_details(payment_method)
        
        expect(user.card_brand).to eq('mastercard')
        expect(user.card_last4).to eq('9876')
        expect(user.card_exp_month).to eq(11)
        expect(user.card_exp_year).to eq(2026)
      end
    end

    describe '#display_name' do
      it 'returns user name if present' do
        user = build(:user, name: 'John Doe')
        expect(user.display_name).to eq('John Doe')
      end

      it 'returns email prefix if name is blank' do
        user = build(:user, name: '', email: 'john.doe@example.com')
        expect(user.display_name).to eq('john.doe')
      end
    end

    describe 'notification preferences' do
      let(:user) { build(:user, notification_preferences: { email_updates: true, marketing: false }) }

      describe '#notification_enabled?' do
        it 'returns true if notification type is enabled' do
          expect(user.notification_enabled?(:email_updates)).to be_truthy
        end

        it 'returns false if notification type is disabled' do
          expect(user.notification_enabled?(:marketing)).to be_falsey
        end

        it 'returns false if notification_preferences is nil' do
          nil_prefs_user = build(:user, notification_preferences: nil)
          expect(nil_prefs_user.notification_enabled?(:any_type)).to be_falsey
        end
      end

      describe '#toggle_notification' do
        it 'toggles notification preference from true to false' do
          expect {
            user.toggle_notification(:email_updates)
          }.to change { user.notification_enabled?(:email_updates) }.from(true).to(false)
        end

        it 'toggles notification preference from false to true' do
          expect {
            user.toggle_notification(:marketing)
          }.to change { user.notification_enabled?(:marketing) }.from(false).to(true)
        end

        it 'initializes preferences if nil' do
          nil_prefs_user = build(:user, notification_preferences: nil)
          nil_prefs_user.toggle_notification(:new_type)
          expect(nil_prefs_user.notification_enabled?(:new_type)).to be_truthy
        end
      end
    end
  end
end
