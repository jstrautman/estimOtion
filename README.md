## estimOtion ##

A web-based version of the agile estimation game.  Connects to a
separate JIRA instance to get the list of issues to be estimated.


## Installing ##

* Copy the estimotion_config.yml.example to estimotion_config.yml.
  Update with your configuration.  Data will be persisted to a local sqlite
  database unless a connection is specified in ENV['DATABASE_URL'].
* Run ./start.sh


## Versions ##

### Innovation Day 25-Oct-2013 ###

* Now connects to Greenhopper's rapid boards.  To start a game, you can
  specify either a JQL query (as before) or pick a rapid board mode.  In rapid
  board mode, all unestimated issues in any future sprint will be added to
  the game.  Issues in the backlog of the rapid board (not assigned to a sprint)
  will be excluded.
* Allows choosing estimate values and saving them to JIRA, using powers of 2.
* Issues can be added to an existing game by dragging and dropping the URL of the
  issue onto the candidate pile.
* Compacted UI.  Cards will partially stack on top of each other once placed
  into columns, which should make larger games easier to view.
* REST endpoints to expose some of the underlying JIRA functionality.  Most of
  these are not used directly by the game, but were useful in debugging, and
  might be helpful for extending further.


## To do/known bugs ##

* Add Firefox support (due to a Javascript security error)
* Add support for simultaneous games.  (Running two games in the same
  browser currently causes updates to be posted to both games.)
* Previous versions allowed users to drag issues back into the candidate
  piles.  The update to allow drag-and-drop of external URLs disabled moving
  issues already in the game back to the candidate pile.  For now, use the "?
  pile instead if you want to revisit an issue.
* Validate URLs for drag-and-drop.  The URL is just stripped down to everything
  after the last slash, but there's no guarantee that we're even looking at a URL
  from the right JIRA server.  The ruby server will handle this gracefully, but
  extra validation in the UI would be good.
* Improve performance of external API calls.  Every method creates is own SOAP
  connection, which is a little more overhead than needed, especially when starting
  a game in rapid board mode and loading each issue one at a time.
* Handle changes outside of the game.  To save on SOAP calls, existing estimates
  for issues are saved in the database, and estimates are changed only when the
  UI element differs from the last saved value.  It's possible that if the
  estimate is also changed in JIRA, we would not notice the values are out of
  sync.  It would also be nice to refresh values if, say, a title were changed.

