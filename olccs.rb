require 'singleton'

require 'fiber'
require 'rack/fiber_pool'

require 'sinatra/base'

require 'nokogiri'
require 'yaml'
require 'json'

require 'eventmachine'
require 'em-synchrony'

require 'pp'

require_relative 'lib/es.rb'
require_relative 'lib/post.rb'
require_relative 'lib/board.rb'

class Configuration
  include Singleton
  
  attr_reader :boards, :es
  
  def init
    config_global = YAML.load_file('config/config.yml')
    config_boards = YAML.load_file('config/boards.yml')
    
    @es = config_global['global']['es']
    #ES.instance.address=config_global['global']['es']
    
    @boards = Hash.new
    config_boards.each_pair do |b,c|
      @boards[b] = Board.new(b,c['getURL'],c['postURL'], c['postParameter'], c['lastIdParameter'] || "last")
      @boards[b].index
    end
    
  end
end

EM.synchrony do

  Configuration.instance.init

  EventMachine::PeriodicTimer.new(30) do
    Configuration.instance.boards.each_pair do |b,c|
      Fiber.new {
        new,total,secs = c.index
        puts "#{c.name} indexed in #{secs} seconds, #{new} new posts"
      }.resume
    end      
  end

  class Olccs < Sinatra::Base
    
    use Rack::FiberPool
    use Rack::CommonLogger
    use Rack::Lint
    set :root, File.dirname(__FILE__) + '/static'

    configure do
      set(:boards) {
        Configuration.instance.boards
      }
    end

    get '/:n/xml' do |n|
      content_type :xml
      result = settings.boards[n].xml
      body result
    end
    
    get '/:n/json' do |n|
      content_type :json
      result = settings.boards[n].backend
      body result
    end
 
    post '/:n/post' do |n|
      content_type :text
      result = settings.boards[n].post(request.cookies, request.user_agent)
      body result
    end

    get '/backend.php' do
      puts "+++++++++++++++++++++++++++++++++++++> BACKEND for #{params[:url]}"
      content_type :xml
      b = settings.boards.select { |k, v| v.getURL == params[:url] }
      result = b.to_a[0][1].xml 
      body result
    end

    post '/post.php' do
      puts "++++++++++++++++++++++++++++++++++++++> POST for #{params[:posturl]}"
      content_type :text
      b = settings.boards.select { |k, v| v.postURL == params[:posturl] }.to_a[0][1]
      b.post(params[:cookie], params[:ua], params[:postdata])
      body "plop"
    end
    
    get '/' do
      body 'Hello World!'
    end
  end

  Olccs.run!

end
  
