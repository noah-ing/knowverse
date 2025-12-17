require 'rails_helper'

RSpec.describe Users::ProfilesController, type: :controller do
  let(:user) { create(:user) }
  let(:valid_attributes) { { name: 'Updated Name' } }
  let(:invalid_attributes) { { name: 'a' * 101 } } # Name too long

  describe 'authentication' do
    it 'redirects unauthenticated users to sign in' do
      get :show
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  context 'when signed in' do
    before { sign_in user }

    describe 'GET #show' do
      it 'assigns the current user as @user and renders the show template' do
        get :show
        
        expect(assigns(:user)).to eq(user)
        expect(response).to render_template(:show)
      end
    end

    describe 'GET #edit' do
      it 'assigns the current user as @user and renders the edit template' do
        get :edit
        
        expect(assigns(:user)).to eq(user)
        expect(response).to render_template(:edit)
      end
    end

    describe 'PATCH #update' do
      context 'with valid params' do
        it 'updates the user profile and redirects to show' do
          patch :update, params: { user: valid_attributes }
          
          user.reload
          expect(user.name).to eq('Updated Name')
          expect(response).to redirect_to(users_profile_path)
          expect(flash[:notice]).to include('Profile was successfully updated')
        end
        
        it 'handles avatar uploads' do
          # Create a test file for avatar upload
          file_path = Rails.root.join('spec', 'fixtures', 'files', 'avatar.jpg')
          
          # Create the directory if it doesn't exist
          FileUtils.mkdir_p(File.dirname(file_path)) unless File.exist?(File.dirname(file_path))
          
          # Create a sample image file if it doesn't exist
          unless File.exist?(file_path)
            File.open(file_path, 'wb') do |f|
              f.write('fake image content')
            end
          end
          
          # Create a file upload object
          avatar_file = fixture_file_upload(file_path, 'image/jpeg')
          
          patch :update, params: { user: { avatar: avatar_file } }
          
          user.reload
          expect(user.avatar).to be_attached
          expect(response).to redirect_to(users_profile_path)
        end
      end

      context 'with invalid params' do
        it 'does not update the user and renders the edit template' do
          original_name = user.name
          
          patch :update, params: { user: invalid_attributes }
          
          user.reload
          expect(user.name).to eq(original_name)
          expect(response).to render_template(:edit)
        end
      end
    end
  end
end
