require 'rails_helper'

RSpec.describe Subscriptions::SubscriptionsController, type: :controller do
  let(:user) { create(:user, :with_subscription) }
  
  before do
    sign_in user
    allow(Stripe::Subscription).to receive(:retrieve).and_return(
      double(
        id: user.stripe_subscription_id,
        status: 'active',
        current_period_end: (Time.now.to_i + 30.days.to_i)
      )
    )
  end
  
  describe 'GET #show' do
    it 'assigns the subscription and renders the show template' do
      get :show
      
      expect(assigns(:subscription)).not_to be_nil
      expect(response).to render_template(:show)
    end
  end
  
  describe 'POST #cancel' do
    before do
      allow(Stripe::Subscription).to receive(:update).and_return(
        double(
          id: user.stripe_subscription_id,
          status: 'active',
          cancel_at_period_end: true
        )
      )
    end
    
    it 'updates the subscription to cancel at period end' do
      post :cancel
      
      expect(Stripe::Subscription).to have_received(:update).with(
        user.stripe_subscription_id,
        { cancel_at_period_end: true }
      )
      
      user.reload
      expect(user.subscription_status).to eq('canceled')
      expect(flash[:notice]).to include('Your subscription has been canceled')
      expect(response).to redirect_to(dashboard_path)
    end
    
    it 'handles Stripe errors' do
      allow(Stripe::Subscription).to receive(:update).and_raise(Stripe::StripeError.new('Test error'))
      
      post :cancel
      
      expect(flash[:alert]).to eq('Test error')
      expect(response).to redirect_to(dashboard_path)
    end
  end
  
  describe 'POST #resume' do
    let(:canceled_user) { create(:user, :canceled) }
    
    before do
      sign_in canceled_user
      allow(Stripe::Subscription).to receive(:retrieve).and_return(
        double(
          id: canceled_user.stripe_subscription_id,
          status: 'canceled',
          current_period_end: (Time.now.to_i + 30.days.to_i)
        )
      )
      allow(Stripe::Subscription).to receive(:update).and_return(
        double(
          id: canceled_user.stripe_subscription_id,
          status: 'active',
          cancel_at_period_end: false
        )
      )
    end
    
    it 'resumes a canceled subscription' do
      post :resume
      
      expect(Stripe::Subscription).to have_received(:update).with(
        canceled_user.stripe_subscription_id,
        { cancel_at_period_end: false }
      )
      
      canceled_user.reload
      expect(canceled_user.subscription_status).to eq('active')
      expect(flash[:notice]).to include('Your subscription has been resumed')
      expect(response).to redirect_to(dashboard_path)
    end
    
    it 'handles Stripe errors' do
      allow(Stripe::Subscription).to receive(:update).and_raise(Stripe::StripeError.new('Test error'))
      
      post :resume
      
      expect(flash[:alert]).to eq('Test error')
      expect(response).to redirect_to(dashboard_path)
    end
  end
  
  describe 'before_action :set_subscription' do
    it 'redirects to plans page if user has no subscription' do
      user.update(stripe_subscription_id: nil)
      
      get :show
      
      expect(flash[:alert]).to include("You don't have an active subscription")
      expect(response).to redirect_to(subscriptions_plans_path)
    end
    
    it 'handles Stripe errors when retrieving subscription' do
      allow(Stripe::Subscription).to receive(:retrieve).and_raise(Stripe::StripeError.new('Test error'))
      
      get :show
      
      expect(flash[:alert]).to eq('Test error')
      expect(response).to redirect_to(dashboard_path)
    end
  end
end
