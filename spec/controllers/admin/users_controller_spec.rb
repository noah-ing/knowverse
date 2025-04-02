require 'rails_helper'

RSpec.describe Admin::UsersController, type: :controller do
  let(:admin_user) { create(:user, :admin) }
  let(:regular_user) { create(:user) }
  let(:user_to_manage) { create(:user) }
  let(:plan) { create(:plan) }

  describe 'authorization' do
    it 'redirects non-admin users to root path' do
      sign_in regular_user
      get :index
      
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to include("You don't have permission")
    end

    it 'allows admin users to access the controller' do
      sign_in admin_user
      get :index
      
      expect(response).to be_successful
      expect(response).to render_template(:index)
    end
  end

  context 'when signed in as admin' do
    before { sign_in admin_user }

    describe 'GET #index' do
      before do
        create_list(:user, 3)
      end

      it 'assigns @users and renders the index template' do
        get :index
        
        expect(assigns(:users)).not_to be_nil
        expect(assigns(:users).count).to be >= 3 # at least our created users
        expect(response).to render_template(:index)
      end
    end

    describe 'GET #search' do
      before do
        create(:user, email: 'test123@example.com')
        create(:user, email: 'another@example.com')
      end

      it 'returns users matching the query' do
        get :search, params: { query: 'test123' }
        
        expect(assigns(:users).count).to eq(1)
        expect(assigns(:users).first.email).to eq('test123@example.com')
        expect(response).to render_template(:index)
      end

      it 'returns all users when query is blank' do
        get :search, params: { query: '' }
        
        expect(assigns(:users).count).to be >= 2
        expect(response).to render_template(:index)
      end
    end

    describe 'GET #show' do
      it 'assigns @user and renders the show template' do
        get :show, params: { id: user_to_manage.id }
        
        expect(assigns(:user)).to eq(user_to_manage)
        expect(response).to render_template(:show)
      end
    end

    describe 'GET #edit' do
      it 'assigns @user and renders the edit template' do
        get :edit, params: { id: user_to_manage.id }
        
        expect(assigns(:user)).to eq(user_to_manage)
        expect(response).to render_template(:edit)
      end
    end

    describe 'PATCH #update' do
      context 'with valid params' do
        it 'updates the user and redirects to show' do
          patch :update, params: { id: user_to_manage.id, user: { admin: true } }
          
          user_to_manage.reload
          expect(user_to_manage.admin).to be_truthy
          expect(response).to redirect_to(admin_user_path(user_to_manage))
          expect(flash[:notice]).to include('successfully updated')
        end
      end

      context 'with invalid params' do
        it 'renders the edit template' do
          # Force validation error by making email blank
          allow_any_instance_of(User).to receive(:update).and_return(false)
          
          patch :update, params: { id: user_to_manage.id, user: { email: '' } }
          
          expect(response).to render_template(:edit)
        end
      end
    end

    describe 'POST #update_subscription' do
      it 'updates the user subscription and redirects to show' do
        post :update_subscription, params: { id: user_to_manage.id, plan_id: plan.id }
        
        user_to_manage.reload
        expect(user_to_manage.stripe_subscription_id).to eq(plan.stripe_price_id)
        expect(user_to_manage.subscription_status).to eq('active')
        expect(response).to redirect_to(admin_user_path(user_to_manage))
        expect(flash[:notice]).to include("Subscription updated to #{plan.name}")
      end
    end

    describe 'POST #deactivate' do
      it 'deactivates the user account and redirects to show' do
        post :deactivate, params: { id: user_to_manage.id }
        
        user_to_manage.reload
        expect(user_to_manage.subscription_status).to eq('canceled')
        expect(response).to redirect_to(admin_user_path(user_to_manage))
        expect(flash[:notice]).to include('User account deactivated')
      end
    end

    describe 'POST #reactivate' do
      before do
        user_to_manage.update(subscription_status: 'canceled')
      end

      it 'reactivates the user account and redirects to show' do
        post :reactivate, params: { id: user_to_manage.id }
        
        user_to_manage.reload
        expect(user_to_manage.subscription_status).to eq('active')
        expect(response).to redirect_to(admin_user_path(user_to_manage))
        expect(flash[:notice]).to include('User account reactivated')
      end
    end

    describe 'POST #send_magic_link' do
      it 'enqueues a job to send a magic link and redirects to show' do
        expect {
          post :send_magic_link, params: { id: user_to_manage.id }
        }.to have_enqueued_job(MagicLinkMailerJob)
        
        expect(response).to redirect_to(admin_user_path(user_to_manage))
        expect(flash[:notice]).to include("Magic link sent to #{user_to_manage.email}")
      end
    end
  end
end
