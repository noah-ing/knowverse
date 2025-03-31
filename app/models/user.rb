class User < ApplicationRecord
  devise :magic_link_authenticatable, :database_authenticatable, :registerable, :recoverable, :rememberable, :validatable
end
