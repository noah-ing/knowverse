module StripeTestHelper
  def stub_stripe_customer_create
    allow(Stripe::Customer).to receive(:create).and_return(
      double(
        id: "cus_#{SecureRandom.alphanumeric(14)}",
        email: 'test@example.com',
        name: 'Test User'
      )
    )
  end

  def stub_stripe_customer_retrieve
    allow(Stripe::Customer).to receive(:retrieve).and_return(
      double(
        id: "cus_#{SecureRandom.alphanumeric(14)}",
        email: 'test@example.com',
        name: 'Test User'
      )
    )
  end

  def stub_stripe_subscription_create
    allow(Stripe::Subscription).to receive(:create).and_return(
      double(
        id: "sub_#{SecureRandom.alphanumeric(14)}",
        status: 'active',
        current_period_end: (Time.now.to_i + 30.days.to_i)
      )
    )
  end

  def stub_stripe_subscription_cancel
    allow(Stripe::Subscription).to receive(:update).and_return(
      double(
        id: "sub_#{SecureRandom.alphanumeric(14)}",
        status: 'canceled'
      )
    )
  end

  def stub_stripe_payment_method_attach
    allow(Stripe::PaymentMethod).to receive(:attach).and_return(
      double(
        id: "pm_#{SecureRandom.alphanumeric(14)}",
        card: double(
          brand: 'visa',
          last4: '4242',
          exp_month: 12,
          exp_year: Time.current.year + 2
        )
      )
    )
  end

  def stub_stripe_payment_method_list
    allow(Stripe::PaymentMethod).to receive(:list).and_return(
      double(
        data: [
          double(
            id: "pm_#{SecureRandom.alphanumeric(14)}",
            card: double(
              brand: 'visa',
              last4: '4242',
              exp_month: 12,
              exp_year: Time.current.year + 2
            )
          )
        ]
      )
    )
  end

  def stub_stripe_event(event_type, object_type, object_attributes = {})
    event_data = {
      'id' => "evt_#{SecureRandom.alphanumeric(14)}",
      'type' => event_type,
      'data' => {
        'object' => {
          'object' => object_type,
          'id' => "#{object_type.slice(0, 3)}_#{SecureRandom.alphanumeric(14)}"
        }.merge(object_attributes)
      }
    }
    
    double(Stripe::Event, event_data)
  end
end

RSpec.configure do |config|
  config.include StripeTestHelper
end
