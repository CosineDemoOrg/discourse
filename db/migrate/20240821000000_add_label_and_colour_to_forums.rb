# frozen_string_literal: true

class AddLabelAndColourToForums < ActiveRecord::Migration[6.0]
  def change
    add_column :forums, :label, :string, limit: 100
    add_column :forums, :colour, :string, limit: 20
  end
end