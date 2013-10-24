require 'rubygems'
require 'dm-core'
require 'dm-migrations'
require 'dm-serializer'
require 'logger'

class JiraCard
  include DataMapper::Resource
  property :id, Serial
  property :jira_card_id, String
  property :ticket_number, String
  property :summary, String
  property :location, String, :default => "card-pile"
  property :updated_at, Time
  property :estimate, Integer
  property :sprint, String
  property :global_rank, Integer

  belongs_to :game

  LOGGER = Logger.new(STDERR)

  def initialize(issue, game = nil)
    jira_card_id = issue.key.gsub("-", "")
    self.jira_card_id = jira_card_id
    self.ticket_number = issue.key
    self.summary = issue.summary
    self.game = game
  end
end
