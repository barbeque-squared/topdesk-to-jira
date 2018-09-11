require 'active_record'

class Item < ActiveRecord::Base
  validates :topdesk_reference, presence: true
end
