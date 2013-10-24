$(function() {

  $("#new-game-header").click(function() {
    $("#new-game-form").toggle("slow");
  });

  $("#join-game-header").click(function() {
    $("#join-game-form").toggle("slow");
  });

  $("#new-game-form").submit(function() {
    if($("#game-name").val() == "Enter a game title..." ||
            (($("#game-jql").val() == "Enter your Jira JQL here...") && $("game-rapid-board-id").val() == "")) {
      alert("Please enter a game name and JQL query.");
      return false;    
    }
  });

  toggleGameType = function() {
    rapid_board = $("#game-type-rapid_board").is(":checked");
    if (rapid_board) {
      $("#game-rapid-board-id").removeAttr("disabled");
      $("#game-jql").attr("disabled", true);
    }
    else {
      $("#game-jql").removeAttr("disabled");
      $("#game-rapid-board-id").attr("disabled", true);
    }
  }

  $("#game-type-rapid_board").click(toggleGameType);
  $("#game-type-jql").click(toggleGameType);

    $("#join-game-form").submit(function() {
    if($("#game-id-select").val() == "") {
      alert("Please select a game to join.");
      return false;    
    }
  });

});
