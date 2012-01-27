require 'singleton'

require 'uri'
require 'cgi'
require 'fiber'
require 'rack/fiber_pool'

require 'sinatra/base'

require 'nokogiri'
require 'yaml'
require 'json'

require 'eventmachine'
require 'em-synchrony'

require 'log4r'
require 'logger'
class ::Logger; alias_method :write, :<<; end

require 'pp'

require_relative 'lib/es.rb'
require_relative 'lib/post.rb'
require_relative 'lib/board.rb'

log = Log4r::Logger.new("olccs")
log.level = Log4r::ERROR

o = Log4r::RollingFileOutputter.new("f1", :filename => "./olccs.log", :maxsize => 1048576, :maxtime => 86400)
o.formatter = Log4r::PatternFormatter.new(:pattern => "[%l] %d :: %m")
log.outputters << o


class Configuration
  include Singleton
  
  attr_reader :boards, :es
  
  def init
    log = Log4r::Logger['olccs']
    config_global = YAML.load_file('config/config.yml')
    config_boards = YAML.load_file('config/boards.yml')
    
    @es = config_global['global']['es']
    #ES.instance.address=config_global['global']['es']
    
    @boards = Hash.new
    config_boards.each_pair do |b,c|
      begin
        @boards[b] = Board.new(b,c['getURL'],c['postURL'], c['postParameter'], c['lastIdParameter'] || "last", c['cookieURL'], c['cookieName'], c['rememberMeParameter'] || "remember_me", c['userParameter'], c['pwdParameter'])
        @boards[b].index
        log.info("Board #{b} initialized")
      rescue Exception => e
        log.error("Board #{b} fail! #{e}")
      end
    end
    
  end
end

EM.synchrony do

  Configuration.instance.init

  EventMachine::PeriodicTimer.new(30) do
    Configuration.instance.boards.each_pair do |b,c|
      Fiber.new {
        begin
          new,total,secs = c.index
          log.info "#{c.name} indexed in #{secs} seconds, #{new} new posts"
        rescue Exception => e
          log.error "#{c.name} fucked up #{e}"
        end
      }.resume
    end      
  end

  class Olccs < Sinatra::Base
    
  
    def add_boards(boards)
      
      @builder = Nokogiri::XML::Builder.new {
        boards {
          boards.each do |b|
            _xml = Nokogiri::XML(b)
            parent.add_child(_xml.root)
          end
        }
      }
      
      return @builder
    end

    use Rack::FiberPool
    #use Rack::CommonLogger, Logger.new('access.log', "weekly")
    use Rack::Deflater
    use Rack::Lint
    set :views, File.dirname(__FILE__) + '/views'
    set :public, File.dirname(__FILE__) + '/static'

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
      result = settings.boards[n].json
      body result
    end
 
    get '/:n/historique.plop' do |n|
      content_type :html

      @from = params[:from] || (Time.now-3600).strftime("%Y%m%d%H%M%S")
      @to = params[:to] || Time.now.strftime("%Y%m%d%H%M%S")
      @list = settings.boards[n].historique(@from,@to)

      body do
        erb :historique
      end
    end

    get '/:n/stats.plop' do |n|
      content_type :html

      @stats = settings.boards[n].stats
      @histogramme = settings.boards[n].histogramme
      #puts @stats
      
      body do
        erb :stats
      end
    end
    
    post '/:n/post' do |n|
      content_type :text
      result = settings.boards[n].post(request.cookies, request.user_agent,params[:message],request)
      body result
    end

    post '/:n/login' do |n|
      content_type :text
      settings.boards[n].login(params[:user], params[:password], request.user_agent).each do |cookie|
        response.set_cookie(cookie[:name], :value => cookie[:value], :domain => request.host, :path => request.path.split('/')[0..-2].join('/'), :expires => cookie[:expires_at])
      end
      body "OK"
    end

    get '/backends' do
      content_type :xml
      boards_params = JSON.parse(params[:boards])
      boards = Array.new
      
      boards_params.each do |b|
        boards << settings.boards[b[0]].xml(b[1])
      end

      body add_boards(boards).to_xml
    end

    get '/:n/search' do |n|
      log = Log4r::Logger['olccs']
      content_type :xml
      log.error("==> QUERY #{params[:query]}")
      s = settings.boards[n].search(params[:query])
      body s
    end

    get '/backend.php' do
      content_type :xml

      log = Log4r::Logger['olccs']
      log.debug "+> BACKEND for #{params[:url]}"

      board = URI.parse(params[:url])
      board_name = board.host
      board_query = board.query
      log.debug "+> #{board_query}"
      if !board_query.nil? then
        lparam = CGI.parse(board_query)['last']
        if !lparam.nil? then 
          l = CGI.parse(board_query)['last'][0]
          if l.nil? or l == "" then
            l = -1
          end
        else
          l = -1
        end
      end

      b = settings.boards.select { |k, v|
        URI.parse(v.getURL).host == board_name
      }

      result = b.to_a[0][1].xml(l) 
      body result
    end

    post '/post.php' do
      content_type :text
      log = Log4r::Logger['olccs']
      log.debug "+> POST for #{params[:posturl]}"

      board_name = URI.parse(params[:posturl]).host
      b = settings.boards.select { |k, v|
        URI.parse(v.postURL).host == board_name
      }.to_a[0][1]
      b.post(params[:cookie], params[:ua], params[:postdata], request)
      body "plop"
    end
    
    get '/totoz.php' do
      content_type :xml
      log = Log4r::Logger['olccs']
      log.error ">> GET TOTOZ #{params[:url]}"

      url = params[:url].sub(/\{question\}/,'?')
      r = EventMachine::HttpRequest.new(url).get
      body r.response
    end

    get '/boards.xml' do
      content_type :xml
      @boards = settings.boards
      body do
        nokogiri :boards
      end
    end
  end

  Olccs.run!

end
