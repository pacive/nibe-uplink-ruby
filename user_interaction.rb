# frozen_string_literal: true

# Module for handling commandline user interactions
module UI
  def self.input(message, &block)
    puts message
    yield if block_given?
    STDOUT.flush
    STDIN.gets.chomp
  end
end
