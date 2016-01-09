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
end

def getPlayerFromIP(ip)
	$players.each do |cP|
		if cP.ip == ip
			return cP
		end
	end
end

def getSockIP(sock)
	port, ip = Socket.unpack_sockaddr_in(sock.get_peername)
	return ip
end

def getSockFromIP(ip)
	$socketClients.each do |ws|
		if getSockIP(ws) == ip
			return ws
		end
	end
end

def sendToAll(msg)
	$socketClients.each do |socket|
		socket.send msg
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
$NUMBER_OF_WHITE_CARDS = 367
$NUMBER_OF_BLACK_CARDS = 6
$CARDS_IN_A_HAND = 12
$MAX_TIME = 25
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
#players = a list of players w/ sensitive stuff removed
$GAME_STATE = {currentScene: 0, blackCard: rand(0 .. $NUMBER_OF_BLACK_CARDS - 1), timer: $MAX_TIME, placedCards: [], cardChooser: 0, players: serializedPlayers()}

def sendGameState()
	sendToAll JSON.generate({type: "gameState", data: $GAME_STATE})
end

def updateGame() 
	loop do
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
			$socketClients.each do |ws|
				ws.send JSON.generate({type: "inventory", data: {inventory: getPlayerFromIP(getSockIP(ws)).card_inventory, can_place_cards: getPlayerFromIP(getSockIP(ws)).can_place_cards}})
			end
		end
		sleep 1
	end
end
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
			$players << Player.new(params["nick"], request.ip)
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
			$socketClients << ws
			puts getSockIP(ws)
			ws.send JSON.generate({type: "inventory", data: {inventory: getPlayerFromIP(getSockIP(ws)).card_inventory, can_place_cards: getPlayerFromIP(getSockIP(ws)).can_place_cards}})
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
						$GAME_STATE[:placedCards] << {card: card, player: getPlayerIndexFromIP(getSockIP(ws))}
					end
					$players[getPlayerIndexFromIP(getSockIP(ws))].card_inventory = tempInventory
					$players[getPlayerIndexFromIP(getSockIP(ws))].can_place_cards = false
					ws.send JSON.generate({type: "inventory", data: {inventory: getPlayerFromIP(getSockIP(ws)).card_inventory, can_place_cards: getPlayerFromIP(getSockIP(ws)).can_place_cards}})
				end
			when "chooseCard" #called when the card chooser chooses
				if (getPlayerFromIP(getSockIP(ws)).)
			end
		end

		ws.onclose do
			#$players.delete(getPlayerFromIP(getSockIP(ws)))
			#$socketClients.delete(ws)
		end
	end

	CardPage.run! :port => 25565, :bind => "0.0.0.0"
end