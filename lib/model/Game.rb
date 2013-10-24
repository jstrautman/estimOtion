require 'rubygems'
require 'dm-core'
require 'dm-migrations'
require 'dm-serializer'
require 'dm-validations'

class Game 
  include DataMapper::Resource
	property :id, Serial
	property :game_name, String
    property :rapid_board, Integer

  has n, :game_columns
  has n, :jira_cards

  validates_presence_of :game_name
  validates_uniqueness_of :game_name
end
