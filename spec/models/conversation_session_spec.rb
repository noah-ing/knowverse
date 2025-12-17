require 'rails_helper'

RSpec.describe ConversationSession, type: :model do
  describe 'associations' do
    it { should belong_to(:organization) }
    it { should belong_to(:user) }
    it { should have_many(:conversation_messages).dependent(:destroy) }
  end

  describe 'validations' do
    it { should validate_presence_of(:session_id) }
    it { should validate_uniqueness_of(:session_id) }
  end

  describe 'scopes' do
    let!(:active_session) { create(:conversation_session, status: 'active') }
    let!(:completed_session) { create(:conversation_session, :completed) }
    let!(:archived_session) { create(:conversation_session, :archived) }

    describe '.active' do
      it 'returns only active sessions' do
        expect(ConversationSession.active).to include(active_session)
        expect(ConversationSession.active).not_to include(completed_session, archived_session)
      end
    end

    describe '.recent' do
      it 'returns sessions ordered by most recent' do
        old_session = create(:conversation_session, created_at: 1.week.ago)
        new_session = create(:conversation_session, created_at: 1.hour.ago)

        results = ConversationSession.recent
        expect(results.first).to eq(new_session)
      end
    end
  end

  describe '#add_message' do
    let(:session) { create(:conversation_session) }

    it 'creates a new message in the session' do
      expect {
        session.add_message(role: 'user', content: 'Hello')
      }.to change { session.conversation_messages.count }.by(1)
    end

    it 'returns the created message' do
      message = session.add_message(role: 'assistant', content: 'Hi there!')
      expect(message).to be_a(ConversationMessage)
      expect(message.content).to eq('Hi there!')
    end
  end

  describe '#message_count' do
    it 'returns the number of messages' do
      session = create(:conversation_session, :with_messages, message_count: 6)
      expect(session.message_count).to eq(6)
    end
  end

  describe '#last_message' do
    let(:session) { create(:conversation_session) }

    before do
      create(:conversation_message, :user, conversation_session: session, created_at: 1.hour.ago)
      create(:conversation_message, :assistant, conversation_session: session, created_at: 30.minutes.ago)
    end

    it 'returns the most recent message' do
      expect(session.last_message.role).to eq('assistant')
    end
  end

  describe '#archive!' do
    let(:session) { create(:conversation_session) }

    it 'sets status to archived' do
      session.archive!
      expect(session.reload.status).to eq('archived')
    end
  end

  describe '#complete!' do
    let(:session) { create(:conversation_session) }

    it 'sets status to completed' do
      session.complete!
      expect(session.reload.status).to eq('completed')
    end
  end

  describe 'factory' do
    it 'creates valid session' do
      session = build(:conversation_session)
      expect(session).to be_valid
    end

    it 'creates session with messages' do
      session = create(:conversation_session, :with_messages, message_count: 4)
      expect(session.conversation_messages.count).to eq(4)
    end
  end
end
