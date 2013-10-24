require 'rubygems'
require 'dm-core'
require 'dm-migrations'
require 'dm-serializer'
require 'dm-validations'

class GameColumn
  include DataMapper::Resource
  property :id, Serial
  property :name, String
  property :estimate, Integer

  belongs_to :game

  validates_uniqueness_of :name
end
