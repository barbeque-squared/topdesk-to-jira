class Initial < ActiveRecord::Migration[4.2]
  def self.up
    create_table "items", force: true do |t|
      t.string   "topdesk_reference", null: false, unique: true
      t.string   "jira_reference", null: false, unique: true
      t.boolean  "closed_in_topdesk", default: false
      t.boolean  "closed_in_jira", default: false
      t.datetime "created_at"
      t.datetime "updated_at"
    end
  end
  def self.down
    drop_table "items"
  end
end
