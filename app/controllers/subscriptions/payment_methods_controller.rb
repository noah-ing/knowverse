module Subscriptions
  class PaymentMethodsController < ApplicationController
    before_action :authenticate_user!
    
    def index
      # Get the customer's payment methods from Stripe
      @payment_methods = []
      
      if current_user.stripe_customer_id.present?
        payment_methods = Stripe::PaymentMethod.list({
          customer: current_user.stripe_customer_id,
          type: 'card'
        })
        
        @payment_methods = payment_methods.data
      end
    end
    
    def new
      # Prepare to add a new payment method
      @stripe_publishable_key = Rails.configuration.stripe[:publishable_key]
    end
    
    def create
      begin
        # Get the payment method ID from the params
        payment_method_id = params[:payment_method_id]
        
        # Create or retrieve the Stripe customer
        customer = current_user.stripe_customer
        
        # Attach the payment method to the customer
        payment_method = Stripe::PaymentMethod.attach(
          payment_method_id,
          { customer: customer.id }
        )
        
        # Set as the default payment method
        Stripe::Customer.update(
          customer.id,
          { invoice_settings: { default_payment_method: payment_method.id } }
        )
        
        # Update the user record with card details
        current_user.update_card_details(payment_method)
        
        flash[:notice] = "Payment method added successfully."
        redirect_to subscriptions_payment_methods_path
      rescue Stripe::CardError => e
        flash[:alert] = e.message
        redirect_to new_subscriptions_payment_method_path
      end
    end
    
    def destroy
      payment_method_id = params[:id]
      
      begin
        # Detach the payment method from the customer
        Stripe::PaymentMethod.detach(payment_method_id)
        
        # If this was the user's only or default payment method, clear card details
        if current_user.card_last4.present?
          # Check if there are any remaining payment methods
          payment_methods = Stripe::PaymentMethod.list({
            customer: current_user.stripe_customer_id,
            type: 'card'
          })
          
          if payment_methods.data.empty?
            # Clear the card details if no payment methods are left
            current_user.update(
              card_brand: nil,
              card_last4: nil,
              card_exp_month: nil,
              card_exp_year: nil
            )
          end
        end
        
        flash[:notice] = "Payment method removed successfully."
      rescue Stripe::StripeError => e
        flash[:alert] = e.message
      end
      
      redirect_to subscriptions_payment_methods_path
    end
  end
end
