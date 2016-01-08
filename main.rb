require "sinatra/base"
require "tilt/erb"
require "em-websocket"
require "eventmachine"
require "json"
require "socket"

$players = []
$socketClients = []
$CARDS = File.read("public/cards.json")
$NUMBER_OF_CARDS = 209
$CARDS_IN_A_HAND = 8

class Player
	attr_accessor :card_inventory #list of card IDs
	attr_reader :nick, :ip
	def initialize(nick, ip)
		@card_inventory = []
		$CARDS_IN_A_HAND.times do 
			@card_inventory << rand(0 .. $NUMBER_OF_CARDS - 1)
		end
		@nick = nick
		@ip = ip
	end
end

def playerExistWithIP(ip)
	exist = false
	$players.each do |cP|
		if cP.ip == ip
			exist = true
		end
	end
	return exist
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
		# Websocket code here
		ws.onopen do |handshake|
			$socketClients << ws
			puts getSockIP(ws)
			ws.send JSON.generate({type: "inventory", data: getPlayerFromIP(getSockIP(ws)).card_inventory})
		end

		ws.onmessage do |msg|
			puts "got data #{msg}"
			$socketClients.each do |socket|
				socket.send msg
			end
		end

		ws.onclose do
			$socketClients.each do |socket|
				socket.send JSON.generate({type: "chat", message: "Someone left the chat!", author: "Server"})
			end
		end
	end

	CardPage.run! :port => 25565, :bind => "0.0.0.0"
end