require "sinatra/base"
require "tilt/erb"
require "websocket-eventmachine-server"
require "eventmachine"
require "json"

$players = []
$socketClients = []

class Player
	attr_accessor :card_inventory #list of card IDs
	attr_reader :nick, :ip
	def initialize(nick, ip)
		@card_inventory = []
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
			puts "making new player w/ nick #{params["nickname"]} and ip #{request.ip}"
			$players << Player.new(params["nick"], request.ip)
			redirect to("/")
		end

		get "/game" do
			if !playerExistWithIP("#{request.ip}")
				redirect to("/setUpPlayer")
			end
			erb :game
		end

		get "cards.json" do
			File.read("cards.json")
		end
	end

	WebSocket::EventMachine::Server.start(:host => '0.0.0.0', :port => 12975) do |ws| # <-- Added |ws|
		# Websocket code here
		ws.onopen do |handshake|
			$socketClients << ws
			ws.send JSON.generate({type: "chat", message: "Welcome to the chat!", author: "Server"})
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