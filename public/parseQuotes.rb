# encoding: UTF-8
require "json"
quotes = File.open("quotes.txt", "r:UTF-8", &:read).split("\n").map(&:rstrip)
p quotes
quoteObject = []
quotes.each_with_index do |quote, index|
	quoteObject << {id: index, quote: quote}
end
File.write("cards.json", JSON.generate(quoteObject));