env = ENV['RACK_ENV'].to_sym

require "bundler/setup"
Bundler.require(:default, env)

Dotenv.load unless env == :production

require './app'
run Sinatra::Application
