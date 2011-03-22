require 'singleton'
require 'sinatra/base'
require 'sinatra/async'

require 'thin'

require 'nokogiri'
require 'yaml'
require 'json'

require 'eventmachine'
require 'em-synchrony'

require 'pp'

require_relative 'lib/es.rb'
require_relative 'lib/post.rb'
require_relative 'lib/board.rb'


EM.synchrony do
  class Settings
    include Singleton

    attr_reader :boards, :es

    def init
      config_global = YAML.load_file('config/config.yml')
      config_boards = YAML.load_file('config/boards.yml')

      @es = config_global['global']['es']
      #ES.instance.address=config_global['global']['es']
      
      @boards = Hash.new
      config_boards.each_pair do |b,c|
        @boards[b] = Board.new(b,c['getURL'],'')
      end

    end
  end

  Settings.instance.init

  EventMachine::PeriodicTimer.new(30) do
    Settings.instance.boards.each_pair do |b,c|
      Fiber.new {
        new,total,secs = c.index
        puts "#{c.name} indexed in #{secs} seconds, #{new} new posts"
      }.resume
    end         
  end

  class App < Sinatra::Base
    register Sinatra::Async
    
    configure do
      set(:boards) {
        Settings.instance.boards
      }
    end

    aget '/:n/xml' do |n|
      content_type :xml
      Fiber.new {
        result = settings.boards[n].xml
        body do
          result
        end
      }.resume
    end
    
    aget '/:n/json' do |n|
      content_type :json
      Fiber.new {
        result = settings.boards[n].backend
        body do
          result
        end
      }.resume
    end
 
    apost '/:n/post' do
      
    end
   
    get '/' do
      'Hello World!'
    end
  end

  App.run!
end
  
