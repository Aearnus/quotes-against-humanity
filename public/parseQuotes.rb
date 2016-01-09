# encoding: UTF-8
require "json"
quotes = File.open("quotes.txt", "r:UTF-8", &:read).split("\n").map(&:rstrip)
authors = File.open("authors.txt", "r:UTF-8", &:read).split("\n").map{|names| names.split(",")}
quoteObject = []
quotes.each_with_index do |quote, index|
	quoteObject << {id: index, quote: quote, authors: authors[index]}
end
File.write("cards.json", JSON.generate(quoteObject));

blackCards = File.open("blackCards.txt", "r:UTF-8", &:read).split("\n").map(&:rstrip)
blackCardObject = []
blackCards.each_with_index do |quote, index|
	blackCardObject << {id: index, quote: quote}
end
File.write("blackCards.json", JSON.generate(blackCardObject));
