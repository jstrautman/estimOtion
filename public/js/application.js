$(function () {
  webSocket.onopen = function (event) {
    var boardData = $('#initial-data').text();
    syncBoard(boardData);
    $("body").prepend('Start Estimating -');
  };

  webSocket.onmessage = function (event) {
    syncBoard(event.data);
  };

  webSocket.onclose = function (event) {
    $("#logo").append('Oh no, something has gone wrong.');
  };

  var $columns = $(".column"),
          $game;


  $columns.droppable({
    accept:"li.drag",
    hoverClass:"column-hover",
    drop:function (event, ui) {
      sendLocationInformation(this, ui);
    }
  });

  $("#card-pile")
          .bind("dragover", false)
          .bind("dragenter", false)
          .bind("drop", function (e) {
            var value = e.originalEvent.dataTransfer.getData("text") ||
                    e.originalEvent.dataTransfer.getData("text/plain");

            var issueKey = value.replace(/.*\//, "");

            if (value) {
              // We're using an old version of jQuery.  This should be .done(...) rather than complete in newer versions.
              $.ajax({url:"/rest/game/" + $game.id + "/issues",
                data:{key:issueKey},
                type:"POST",
                complete:function () {
                  var params = {game:$game.id};
                  webSocket.send(JSON.stringify(params));
                }

              });
            }

            return false;
          });


  $("#discard-pile, #question-pile").droppable({
    accept:"li.drag",
    hoverClass:"column-hover",
    drop:function (event, ui) {
      sendLocationInformation(this, ui);
    }
  });

  function sendLocationInformation(drop, ui) {
    var params = {id:$(ui.draggable).attr("id"),
      game:$game.id,
      location:drop.id};

    webSocket.send(JSON.stringify(params));
  }

  $(".game-column-estimate").change(function () {
    var params = {column:this.id,
      game:$game.id,
      estimate:this.value};

    webSocket.send(JSON.stringify(params));
  });

  $("#save-estimates-button").click(function () {
    $.ajax({type:"POST",
      url:"/rest/game/" + $game.id + "/estimates",
      complete:function () {
        $("#save-estimates-button").animate({ color:"#FFCC33" }, 500, function () {
          $("#save-estimates-button").animate({ color:"#FFFFFF"});
        })
      }
    });
  });

  function syncBoard(boardData) {
    if (boardData != null && boardData != '') {
      try {
        var game_info = jQuery.parseJSON(boardData);

        $game = game_info.game;

        var $updatedColumns = [];

        // Look for any estimates stored in the JSON
        $.each(game_info.columns, function (index, column) {
          var name = column.name;
          var estimate = column.estimate;

          $("#" + name + "-estimate").val(estimate);
        })

        // Look through the cards and move anything that changed
        $.each(game_info.cards, function (index, card) {
          var $thisCard = $("#" + card.jira_card_id);

          // if this is a new card then create it from the template and make it draggable
          if (0 == $thisCard.length) {
            $thisCard = $("#card-template #template-id").clone();
            $thisCard.css('position', '');
            $thisCard[0].id = card.jira_card_id;

            var a = $thisCard.find("#link-template")[0];
            a.href += card.ticket_number;
            a.innerHTML = card.ticket_number;

            $thisCard.find("#summary-template")[0].innerHTML = card.summary;

            $thisCard.draggable({
              opacity:0.45,
              revert:'invalid'
            });
          }

          var actualParentId = '#' + $thisCard.parent().attr('id'),
                  correctParentId = "#" + card.location + "-list";

          if (actualParentId !== correctParentId) {
            var $parentList = $(correctParentId);
            $updatedColumns.push($parentList.parent());
            $thisCard.appendTo($parentList);
          }
        });

        $.each($updatedColumns, function (index, column) {
          column.animate({ backgroundColor:"#Fff97f" }, 500,
                  function () {
                    column.animate({ backgroundColor:'transparent' }, 500,
                            function () {
                              column.css('backgroundColor', '');
                            });
                  })
        });

        // fix the heights of the columns
        var maxHeight = 0;
        $columns.each(function () {
          var height = $(this).find('ul').children().size() * 200;
          maxHeight = height > maxHeight ? height : maxHeight;
        });
        if (maxHeight) {
          $('.column').height(maxHeight);
        }

        // blank out the styles set by drag/drop
        $("li.drag").attr("style", "");

        var cardsLeft = $("#card-pile-list").children().size();
        $("#cards-left").html(cardsLeft);

      } catch (e) {
        // swallow exceptions, because most likely we were given data that is not in json format and
        // we don't need to do anything with it.
      }
    }
  }
});
