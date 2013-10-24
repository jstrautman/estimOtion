require 'rubygems'
require 'jira4r/jira4r'
require 'open-uri'
require 'json'
require_relative 'model/JiraCard'
require 'logger'

class Jira
  SERVER = EstimotionConfig.jira.server
  USERNAME = EstimotionConfig.jira.user
  PASSWORD = EstimotionConfig.jira.password
  RESULTS_LIMIT = EstimotionConfig.jira.result_limit

  LOGGER = Logger.new(STDERR)

  # Returns an array of JIRA issue object (per their SOAP model)
  #
  # Soap:
  #   http://docs.atlassian.com/software/jira/docs/api/rpc-jira-plugin/latest/index.html?com/atlassian/jira/rpc/soap/JiraSoapService.html
  def self.get_issues(jql)
    issues = []

    begin
      jira = Jira4R::JiraTool.new(2, SERVER)
      jira.login(USERNAME, PASSWORD)

      soap_response = jira.getIssuesFromJqlSearch(jql, RESULTS_LIMIT)

      soap_response.collect do |issue|
        issues << issue
      end
    rescue => e
      LOGGER.error(e.to_s)
    end

    issues
  end

  # Returns the full JIRA issue object from SOAP for a given key
  def self.get_issue(key)
    begin
      jira = Jira4R::JiraTool.new(2, SERVER)
      jira.login(USERNAME, PASSWORD)

      soap_response = jira.getIssue(key)

      soap_response
    rescue => e
      LOGGER.error(e.to_s)
    end
  end

  # Get all the rapid boards available in our JIRA instance.
  #
  # These are unpublished APIs so catch any errors and log them without
  # breaking the app.  You can always use manual JQL instead.
  def self.get_rapid_boards()
    begin
      url = "#{SERVER}/rest/greenhopper/1.0/rapidview"

      rest_response = URI.parse(url).read
      views = JSON.parse(rest_response)
      sorted_views = views['views'].sort_by { |a| a['name'].upcase }

      sorted_views
    rescue => e
      LOGGER.error(e.to_s)
      []
    end
  end

  # Get all the sprints in a rapid board (not including the backlog)
  #
  # Another unpublished Greenhopper API, so catch errors
  def self.get_future_sprints(rapid_board_id)
    begin
      url = "#{SERVER}/rest/greenhopper/1.0/sprintquery/#{rapid_board_id}?includeHistoricSprints=false&includeFutureSprints=true"

      rest_response = URI.parse(url).read
      sprints = JSON.parse(rest_response)['sprints']
      future_sprints = sprints.select { |a| a['state'] == "FUTURE" }

      future_sprints
    rescue => e
      LOGGER.error(e.to_s)
      []
    end
  end

  def self.get_custom_field_id(field_name)
    url = "#{SERVER}/rest/api/2/field"

    rest_response = open(URI.parse(url),
                         :http_basic_authentication => [USERNAME, PASSWORD]
    ).to_a.join

    fields = JSON.parse(rest_response).select{|field| field['name'] == field_name}

    if fields[0]
      fields[0]['id']
    else
      nil
    end
  end

  # Creates JiraCard objects for all of the unfinished tickets in a given
  # rapid board and sprint.
  #
  # Explicitly sorts the card by the "Global Rank" field to match what we see
  # in the rapid board, because the current REST API orders by issue key.
  def self.make_cards_for_sprint(rapid_board_id, sprint_id, game = nil)
    cards = []

    url = "#{SERVER}/rest/greenhopper/1.0/rapid/charts/sprintreport?rapidViewId=#{rapid_board_id}&sprintId=#{sprint_id}"

    sprints = get_future_sprints(rapid_board_id).select { |a| a['id'] == sprint_id.to_i }
    sprint_name = sprints[0]['name']

    # Greenhopper throws a 400 if there are no tickets in the specified sprint.
    begin
      rest_response = open(URI.parse(url),
                           :http_basic_authentication => [USERNAME, PASSWORD]
      ).to_a.join
    rescue
      return cards
    end

    # Raw tickets as hashes.  These will contain only some of the fields we
    # want for our JiraCard object.
    tickets = JSON.parse(rest_response)['contents']['incompletedIssues']

    global_rank_field = self.get_custom_field_id("Global Rank")

    # Now convert them to JiraCard objects, loading other fields via the SOAP API
    tickets.each do |ticket|
      issue = get_issue(ticket['key'])

      card = JiraCard.new(issue, game)
      card.estimate = ticket['estimateStatistic']['statFieldValue']['value']
      card.sprint = sprint_name

      global_rank_element = issue.customFieldValues.select{|field| field.customfieldId == global_rank_field}
      if global_rank_element[0]
        card.global_rank = global_rank_element[0].values[0]
        LOGGER.debug("Found global rank #{card.global_rank} for issue #{ticket['key']}")
      end

      #LOGGER.debug("Created card #{card.to_json}")

      cards << card
    end

    cards.sort_by{|card| card.global_rank}
  end

  # Create JiraCards for all the unfinished tickets in sprints on the rapid
  # board (but not counting the backlog).
  def self.make_cards_for_rapid_board(rapid_board_id, game = nil)
    cards = []

    sprints = get_future_sprints(rapid_board_id)

    sprints.each do |sprint|
      cards += self.make_cards_for_sprint(rapid_board_id, sprint['id'], game)
    end

    cards
  end

  # Add an issue to an existing game.
  def self.add_issue_to_game(key, game)
    issue = self.get_issue(key)

    LOGGER.debug(game)
    card = JiraCard.new(issue, game)
    card.game_id = game.id
    card.save!

    return card
  end

  def self.update_estimate(key, estimate)
    jira = Jira4R::JiraTool.new(2, SERVER)
    jira.login(USERNAME, PASSWORD)

    custom_field_id = self.get_custom_field_id("Story Points")

    ticket = jira.getIssue(key)

    custom_field = Jira4R::V2::RemoteFieldValue.new
    custom_field.id = custom_field_id
    # Estimates have to be an array of strings.
    custom_field.values = [estimate.to_s]

    jira.updateIssue(ticket.key, [custom_field])
  end

  # Convenience method for excluding unestimated issues
  def self.filter_unestimated(issues)
    issues.select { |issue| issue.estimate.nil? }
  end
end
