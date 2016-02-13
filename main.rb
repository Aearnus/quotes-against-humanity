require "sinatra/base"
require "tilt/erb"
require "em-websocket"
require "eventmachine"
require "json"
require "socket"


#--------HELPER FUNCTIONS--------
$players = []
$socketClients = []
def playerExistWithIP(ip)
	exist = false
	$players.each do |cP|
		if cP.ip == ip
			exist = true
		end
	end
	return exist
end

def getPlayerIndexFromIP(ip)
	$players.each_with_index do |cP, index|
		if cP.ip == ip
			return index
		end
	end
	return nil
end

def getPlayerFromIP(ip)
	$players.each do |cP|
		if cP.ip == ip
			return cP
		end
	end
	return nil
end

def getSockIP(sock)
	begin
		port, ip = Socket.unpack_sockaddr_in(sock.get_peername)
	rescue
		return nil
	end
	return ip
end

def getSockFromIP(ip)
	$socketClients.each do |ws|
		if getSockIP(ws) == ip
			return ws
		end
	end
	return nil
end

def sendToAll(msg)
	$socketClients.each do |socket|
		if (!socket.error?) 
			socket.send msg
		end
	end
end

def serializedPlayers()
	serialArray = []
	$players.each do |cP|
		serialArray << cP.makeSafe()
	end
	return serialArray
end

#--------GAME OPTIONS--------
$CARDS = File.read("public/cards.json")
$BLACK_CARDS = File.read("public/blackCards.json")
$NUMBER_OF_WHITE_CARDS = 383
$NUMBER_OF_BLACK_CARDS = 97
$CARDS_IN_A_HAND = 12
$MAX_TIME = 40
#--------GAME FUNCTIONS--------
class Player
	attr_accessor :card_inventory, :can_place_cards, :points, :is_card_chooser
	attr_reader :nick, :ip
	def initialize(nick, ip)
		@card_inventory = []
		$CARDS_IN_A_HAND.times do 
			@card_inventory << rand(0 .. $NUMBER_OF_WHITE_CARDS - 1)
		end
		@nick = nick
		@ip = ip
		@can_place_cards = false
		@points = 0
		@is_card_chooser = false
	end
	def makeSafe()
		return {nick: @nick, points: @points, is_card_chooser: @is_card_chooser}
	end
end

#currentScene = 0: choosing cards, 1: 
#blackCard = id of current black card
#timer = current number of countdown clock
#placedCards = array of id's of cards that were placed
#cardChooser = index of the player that's the current cardChooser
#chosenCard = -1 until a card(s) is chosen, and once a card(s) is chosen, it is the index of that card(s)
#players = a list of players w/ sensitive stuff removed
$GAME_STATE = {currentScene: 0, blackCard: rand(0 .. $NUMBER_OF_BLACK_CARDS - 1), timer: $MAX_TIME, placedCards: [], cardChooser: 0, chosenCard: -1, players: serializedPlayers()}

def sendGameState()
	sendToAll JSON.generate({type: "gameState", data: $GAME_STATE})
end

def sendInventory(ws, player)
	ws.send JSON.generate({type: "inventory", data: {inventory: player.card_inventory, can_place_cards: player.can_place_cards, is_card_chooser: player.is_card_chooser}})
end

def updateGame() 
	loop do
		if $players.length > 2
			sendGameState()
			$GAME_STATE[:players] = serializedPlayers()
			$GAME_STATE[:timer] = $GAME_STATE[:timer] - 1
			#skip to end if all players have played cards
			if ($GAME_STATE[:placedCards].length == $players.length - 1) && ($GAME_STATE[:currentScene] == 0) && ($GAME_STATE[:timer] > 5) 
				$GAME_STATE[:timer] = 1
			end
			if $GAME_STATE[:timer] <= 0 
				$GAME_STATE[:currentScene] = ($GAME_STATE[:currentScene] + 1) % 2
				if $GAME_STATE[:currentScene] == 0 #people are choosing cards
					$GAME_STATE[:chosenCard] = -1
					$GAME_STATE[:placedCards] = [] #delete all the previous cards
					$GAME_STATE[:blackCard] = rand(0 .. $NUMBER_OF_BLACK_CARDS - 1)
					$GAME_STATE[:cardChooser] = ($GAME_STATE[:cardChooser] + 1) % $players.length
					$players.each_with_index do |cP, index|
						if index == $GAME_STATE[:cardChooser] #ensure the card chooser can't place a card and stuff
							cP.can_place_cards = false
							cP.is_card_chooser = true
						else
							cP.can_place_cards = true
							cP.is_card_chooser = false
						end
					end
				elsif $GAME_STATE[:currentScene] == 1 #the card chooser is choosing the best card
					$players.each do |cP|
						cP.can_place_cards = false
					end
				end
				$GAME_STATE[:timer] = $MAX_TIME
			end
			#once black card and everything is chosen, resend inventory
			$socketClients.each do |ws|
				if (!ws.error?)
					sendInventory(ws, getPlayerFromIP(getSockIP(ws)))
				end
			end
		end
		sleep 1
	end
end
Thread.abort_on_exception = true
Thread.new do
	puts "opened game update thread"
	updateGame()
end
puts "outside of game update thread"

EventMachine.run do
	class CardPage < Sinatra::Base
		get "/" do
			if !playerExistWithIP("#{request.ip}")
				redirect to("/setUpPlayer")
			else
				redirect to("/game")
			end
		end

		get "/setUpPlayer" do
			erb :setUpPlayer
		end

		post "/setUpPlayer" do
			puts "making new player w/ nick #{params["nick"]} and ip #{request.ip}"
			if !playerExistWithIP(request.ip)
				$players << Player.new(params["nick"], request.ip)
			end
			redirect to("/")
		end

		get "/game" do
			if !playerExistWithIP("#{request.ip}")
				redirect to("/setUpPlayer")
			end
			erb :game
		end
	end

	EventMachine::WebSocket.run(:host => '0.0.0.0', :port => 12975) do |ws| # <-- Added |ws|
		#when someone connects, they need their inventory and initial game state
		ws.onopen do |handshake|
			$socketClients.delete_if {|s| s.error?}
			$socketClients << ws
			puts getSockIP(ws)
			sendInventory(ws, getPlayerFromIP(getSockIP(ws)))
			sendGameState()
		end

		ws.onmessage do |msg|
			puts "got #{msg}"
			message = JSON.parse msg
			case message["type"]
			when "playCard" #called once for both single and multiple cards played
				if (getPlayerFromIP(getSockIP(ws)).can_place_cards == true)
					cardsPlayed = message["data"]
					tempInventory = $players[getPlayerIndexFromIP(getSockIP(ws))].card_inventory
					cardsPlayed.each do |card|
						tempInventory.delete_at(tempInventory.index(card))
						$players[getPlayerIndexFromIP(getSockIP(ws))].card_inventory = $players[getPlayerIndexFromIP(getSockIP(ws))].card_inventory.push(rand(0 .. $NUMBER_OF_WHITE_CARDS - 1))
					end
					$GAME_STATE[:placedCards] << {card: cardsPlayed, player: getPlayerIndexFromIP(getSockIP(ws))}
					$players[getPlayerIndexFromIP(getSockIP(ws))].card_inventory = tempInventory
					$players[getPlayerIndexFromIP(getSockIP(ws))].can_place_cards = false
					sendInventory(ws, getPlayerFromIP(getSockIP(ws)))
					end
			when "chooseCard" #called when the card chooser chooses
				#if the message is from the card chooser and it is his turn to choose
				if (getPlayerFromIP(getSockIP(ws)).is_card_chooser == true) && ($GAME_STATE[:currentScene] == 1)
					$players[getPlayerIndexFromIP(getSockIP(ws))].is_card_chooser = false
					cardIndexChosen = message["data"]
					$GAME_STATE[:chosenCard] = cardIndexChosen
					$GAME_STATE[:timer] = 5
					#award points to the player who placed the winning card(s)
					puts $GAME_STATE
					wonCardsIndex = $GAME_STATE[:chosenCard]
					wonCards = $GAME_STATE[:placedCards][wonCardsIndex]
					wonPlayerIndex = wonCards[:player]
					$players[wonPlayerIndex].points = $players[wonPlayerIndex].points + 1
					sendGameState()
				end
			end
		end

		ws.onclose do
			puts "closed socket"
			$socketClients.delete_if {|s| s.error?}
			puts "deleted socket"
			#$players.each_with_index do |cP, index|
			#	if getSockFromIP(cP.ip) == nil
			#		$players.delete_at(index)
			#	end
			#end
			#$players.delete(getPlayerFromIP(getSockIP(ws)))
			#$socketClients.delete(ws)
		end
	end

	CardPage.run! :port => 25565, :bind => "0.0.0.0"
end