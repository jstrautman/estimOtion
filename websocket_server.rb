require 'rubygems'
require 'em-websocket'
require 'eventmachine'
require 'json'
require 'dm-core'
require 'dm-serializer'
require_relative 'lib/estimotion_config'
require_relative 'lib/model/Game'
require_relative 'lib/model/JiraCard'
require_relative 'lib/model/GameColumn'
require_relative 'lib/estimotion_helpers'

host = '0.0.0.0'
port = EstimotionConfig.websocket_server.port

module FlashPolicyServer
  def receive_data(data)
    send_data(respond_with_policy(data))
  end

  def respond_with_policy(request)
    policy = %Q{<?xml version="1.0"?>
  <!DOCTYPE cross-domain-policy SYSTEM "http://www.macromedia.com/xml/dtds/cross-domain-policy.dtd">
  <cross-domain-policy>
    <allow-access-from domain="opower.com" to-ports="#{EstimotionConfig.websocket_server.port}" />
  </cross-domain-policy>
      }
  end
end

EventMachine.run do
  include EstimotionHelpers

  LOGGER = Logger.new(STDERR)

  # this prevents the "undefined method `include?' for nil:NilClass (NoMethodError)" error
  DataMapper.finalize

  DataMapper.setup(:default, ENV['DATABASE_URL'] || "sqlite3://#{Dir.pwd}/db/game.db")
  @estimation_party = EM::Channel.new

  EventMachine::WebSocket.start(:host => host, :port => port, :debug => true) do |ws|
    # fires when we open a connection
    ws.onopen do
      puts "connection open"

      # Register the estimation party listener
      sid = @estimation_party.subscribe do |msg|
        puts "Sending data to the front end"
        ws.send msg
      end

      # fires when we receive a message on the channel
      ws.onmessage do |msg|
        puts "on message called"
        parsed_message = JSON.parse(msg)

        game = Game.get("#{parsed_message['game']}")

        if parsed_message['id'] != nil
          jira_card = JiraCard.first(:jira_card_id => "#{parsed_message['id']}", :game => game)

          puts "calling jira_card#update() with :location => #{parsed_message['location']}"
          #puts "jira_card.inspect = #{jira_card.inspect}"

          jira_card.update!(:location => "#{parsed_message['location']}", :updated_at => Time.now)
        end

        if parsed_message['column'] != nil
          column_name = parsed_message['column'].gsub /-estimate/, ""
          game_column = GameColumn.first(:name => column_name, :game => game)
          estimate = parsed_message['estimate'];

          LOGGER.debug("Updating #{game_column.to_json} to #{estimate}")
          game_column.update!(:estimate => estimate.empty? ? nil : estimate)
        end

        cards = JiraCard.all(:game => game, :order => [:updated_at.asc])
        game_columns = GameColumn.all(:game => game)

        @estimation_party.push "#{build_json(game, cards, game_columns)}"
      end

      # fires when someone leaves
      ws.onclose do
        @estimation_party.unsubscribe(sid)
        @estimation_party.push "Estimation Party is over for #{sid}."
      end
    end
  end
  puts "Estimation party server started"
end

EventMachine::start_server host, port, FlashPolicyServer
