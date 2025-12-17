require 'rails_helper'

RSpec.describe Users::MagicLinksController, type: :controller do
  describe 'POST #create' do
    context 'with an existing user' do
      let(:user) { create(:user) }

      it 'generates a login token and sends an email' do
        expect {
          post :create, params: { email: user.email }
        }.to have_enqueued_job(MagicLinkMailerJob)

        expect(flash[:notice]).to include("Magic login link sent to #{user.email}")
        expect(response).to redirect_to(root_path)
      end
    end

    context 'with a new email address' do
      let(:email) { 'new.user@example.com' }

      it 'creates a new user, generates a login token and sends an email' do
        expect {
          post :create, params: { email: email }
        }.to change(User, :count).by(1).and have_enqueued_job(MagicLinkMailerJob)

        expect(flash[:notice]).to include("Magic login link sent to #{email}")
        expect(response).to redirect_to(root_path)
      end
    end

    context 'with an invalid email' do
      it 'displays an error message' do
        post :create, params: { email: '' }
        
        expect(flash[:alert]).to include('No user found with that email address')
        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe 'GET #show' do
    context 'with a valid token' do
      let(:user) { create(:user, :with_login_token) }
      let(:token) { user.login_token }

      before do
        user.update(login_token_valid_until: 15.minutes.from_now)
      end

      it 'signs in the user and redirects to dashboard' do
        get :show, params: { login_token: token }
        
        expect(flash[:notice]).to include('You have been signed in successfully')
        expect(response).to redirect_to(dashboard_path)
        expect(controller.current_user).to eq(user)
        
        # Token should be cleared after successful login
        user.reload
        expect(user.login_token).to be_nil
      end
    end

    context 'with an expired token' do
      let(:user) { create(:user, :with_login_token) }
      let(:token) { user.login_token }

      before do
        user.update(login_token_valid_until: 15.minutes.ago)
      end

      it 'displays an error message and redirects to sign in' do
        get :show, params: { login_token: token }
        
        expect(flash[:alert]).to include('Login link expired')
        expect(response).to redirect_to(new_user_session_path)
        expect(controller.current_user).to be_nil
      end
    end

    context 'with an invalid token' do
      it 'displays an error message and redirects to sign in' do
        get :show, params: { login_token: 'invalid-token' }
        
        expect(flash[:alert]).to include('Invalid login link')
        expect(response).to redirect_to(new_user_session_path)
        expect(controller.current_user).to be_nil
      end
    end
  end
end
