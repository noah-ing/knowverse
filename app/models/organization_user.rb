class OrganizationUser < ApplicationRecord
  belongs_to :organization
  belongs_to :user
  
  # Constants
  ROLES = %w[owner admin editor viewer].freeze
  
  # Validations
  validates :role, presence: true, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :organization_id, message: "already belongs to this organization" }
  
  # Scopes
  scope :owners, -> { where(role: 'owner') }
  scope :admins, -> { where(role: 'admin') }
  scope :editors, -> { where(role: 'editor') }
  scope :viewers, -> { where(role: 'viewer') }
  scope :invited, -> { where.not(invitation_token: nil).where(invitation_accepted_at: nil) }
  
  # Callbacks
  before_create :generate_invitation_token, if: -> { invitation_token.blank? }
  after_create :assign_owner_role_for_first_user, if: -> { organization.organization_users.count == 1 }
  
  # Instance methods
  def owner?
    role == 'owner'
  end
  
  def admin?
    role == 'admin' || role == 'owner'
  end
  
  def editor?
    role == 'editor' || admin?
  end
  
  def viewer?
    role == 'viewer' || editor?
  end
  
  def invited?
    invitation_token.present? && invitation_accepted_at.nil?
  end
  
  def accept_invitation!
    update(invitation_accepted_at: Time.current, invitation_token: nil)
  end
  
  def resend_invitation!
    generate_invitation_token
    save
  end
  
  private
  
  def generate_invitation_token
    self.invitation_token = SecureRandom.hex(20)
  end
  
  def assign_owner_role_for_first_user
    update(role: 'owner') if organization.organization_users.count == 1
  end
end
