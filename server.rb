require 'rubygems'
#require 'bundler/setup'
require_relative 'lib/estimotion_config'
require 'erb'
require 'json'
require 'sinatra'
require 'dm-core'
require 'dm-migrations'
require 'dm-serializer'
require_relative 'lib/model/Game'
require_relative 'lib/model/JiraCard'
require_relative 'lib/model/GameColumn'
require_relative 'lib/jira'
require_relative 'lib/estimotion_helpers'
require 'sinatra/flash'
require 'sinatra/content_for'


class EstimOtion < Sinatra::Base
  include EstimotionHelpers

  LOGGER = Logger.new(STDERR)

  set :port, EstimotionConfig.server.port
  set :root, File.dirname(__FILE__)
  set :sessions, true
  set :layout, true

  register Sinatra::Flash

  configure do
    DataMapper.finalize
    DataMapper.setup(:default, ENV['DATABASE_URL'] || "sqlite3://#{Dir.pwd}/db/game.db")
    DataMapper.auto_upgrade!
  end

  helpers Sinatra::ContentFor

  helpers do
    include Rack::Utils
    alias_method :h, :escape_html
  end

  get '/' do
    erb :index, :locals => {
        :games => Game.all,
        :boards => Jira.get_rapid_boards
    }
  end


  # Shows all of the tickets in the current game.
  #
  # This reflects only the state of the database, and will not show estimates
  # that have not been saved to JIRA.
  get '/rest/game/:game_id' do
    game = Game.get(params[:game_id])
    jira_cards = JiraCard.all(:game => game, :order => [:updated_at.asc])

    content_type :json
    jira_cards.to_json
  end

  get '/rest/game' do
    Game.all.to_json
  end

  # Test endpoint showing all the available rapid boards
  get '/rest/rapidboards' do
    Jira.get_rapid_boards.to_json
  end

  # Test endpoint showing all the sprints under a rapid board
  get '/rest/rapidboards/:rapid_board_id/sprints' do
    Jira.get_future_sprints(params[:rapid_board_id]).to_json
  end

  # Test endpoint for showing all of the tickets in a rapid board (excluding backlog)
  #
  # Defaults to exlcuding estimated tickets.
  get '/rest/rapidboards/:rapid_board_id/tickets' do
    include_estimated = params.has_key?('include-estimated')

    tickets = Jira.make_cards_for_rapid_board(params[:rapid_board_id])
    tickets = Jira.filter_unestimated(tickets) unless include_estimated

    tickets.to_json
  end

  # Test endpoint for showing all of the tickets in a rapid board and sprint
  #
  # Defaults to exlcuding estimated tickets.
  get '/rest/rapidboards/:rapid_board_id/sprints/:sprint_id/tickets' do
    include_estimated = params.has_key?('include-estimated')

    tickets = Jira.make_cards_for_sprint(params[:rapid_board_id], params[:sprint_id])
    tickets = Jira.filter_unestimated(tickets) unless include_estimated

    tickets.to_json
  end

  # Test endpoint for all the JiraCards that would be returned by a given JQL query
  get '/rest/query' do
    jql = params['jql']
    issues = Jira.get_issues(jql)

    cards = []

    issues.each do |issue|
      cards << JiraCard.new(issue)
    end

    cards.to_json
  end

  # Adds an issue (by issue key) to an existing game.
  post '/rest/game/:game_id/issues' do
    game = Game.get(params[:game_id])
    key = params['key']

    card = Jira.add_issue_to_game(key, game)
    card.to_json
  end

  # Forecasts the estimates based on the points on each column, but does not
  # change the state of JIRA.  This previews what would happen by posting to
  # the same endpoint.
  get '/rest/game/:game_id/estimates' do
    game = Game.get(params[:game_id])
    estimates = Hash[game.game_columns.all.map { |c| [c.name, c.estimate] }]

    game.jira_cards.each do |card|
      LOGGER.debug("Comparing #{card.ticket_number} -- was #{card.estimate.to_s}, now #{estimates[card.location].to_s} ")
      if card.location && (estimates[card.location].to_s != card.estimate.to_s)
        card.estimate = estimates[card.location]
      end
    end

    game.jira_cards.to_json
  end

  # Updates JIRA and the local database with our estimates for each column.
  post '/rest/game/:game_id/estimates' do
    game = Game.get(params[:game_id])
    estimates = Hash[game.game_columns.all.map { |c| [c.name, c.estimate] }]

    game.jira_cards.each do |card|
      if card.location && (estimates[card.location].to_s != card.estimate.to_s)
        LOGGER.debug("About to update #{card.ticket_number} to #{estimates[card.location]}")
        card.update!(:estimate => estimates[card.location])

        Jira.update_estimate(card.ticket_number, card.estimate)
      end
    end

    game.jira_cards.to_json
  end

  post '/game/join' do
    redirect "/game/#{params['game-id-select']}"
  end

  post '/game/new' do
    LOGGER.info("starting a new game")
    game = Game.new(:game_name => params['game-name'])
    errors = validate_form_input(game, params)

    cards = []

    if errors.empty?
      for i in 1..6 do
        column = GameColumn.new(:name => "column-#{i}", :game => game)
        column.save!
      end
      # make_cards_for_rapid_board already does the casting to JiraCard
      if params.has_key?('game-rapid-board-id')
        # Reverse the card order so the highest-ranked issue shows up first.
        cards = Jira.make_cards_for_rapid_board(params['game-rapid-board-id'], game).reverse

        include_estimated = params.has_key?('include-estimated')
        cards = Jira.filter_unestimated(cards) unless include_estimated
        # but the raw Jira.get_issues does not
      else
        issues = Jira.get_issues(params['game-jql'])
        issues.each do |issue|
          jira_card = JiraCard.new(issue, game)
          cards << jira_card
        end
      end
    end

    if errors.empty? && !cards.empty?
      game.save

      cards.each do |card|
        card.save!
      end

      LOGGER.debug("Starting game #{game.id}")

      redirect "/game/#{game.id}"
    else
      errors << "No issues returned from Jira for the given JQL" if errors.empty? && issues.empty?

      flash["game-name"] = params["game-name"]
      flash["game-jql"] = params["game-jql"]
      flash["errors"] = errors
      redirect '/'
    end
  end

  get '/game/:game_id' do
    game = Game.get(params[:game_id])
    jira_cards = JiraCard.all(:game => game, :order => [:updated_at.asc])

    erb :game, :locals => {
        :host_name => @env['SERVER_NAME'],
        :game => game,
        :json => build_json(game, jira_cards, game.game_columns)
    }
  end

  get '/tasks' do
    game = Game.get(1)
    jira_cards = JiraCard.all(:game => game, :order => [:updated_at.asc])

    erb :tasks, :locals => {
        :host_name => @env['SERVER_NAME'],
        :game => game,
        :json => build_json(game, jira_cards, game.game_columns)
    }

  end

  private

  def validate_form_input(game, params)
    errors = []

    LOGGER.info("Form input: #{params.to_s}")

    # Datamapper validation errors
    if (!game.valid?)
      game.errors.each do |error|
        errors << error
      end
    end

    # Form specific errors
    if params['game-rapid-board-id'] != nil
      if !(params['game-rapid-board-id'] =~ /^[-+]?[0-9]+$/)
        errors << "Rapid board ID must be an integer"
      end
    elsif params['game-jql'] == nil && params['game-jql'].strip.size == 0
      errors << "Must specify rapid board ID or JQL"
    end

    LOGGER.warn("Validation errors processing form: #{errors}") unless errors.empty?

    errors
  end

  run!
end
