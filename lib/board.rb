# -*- coding: utf-8 -*-
require 'rubygems'
require 'httparty'
require 'nokogiri'
require 'hpricot'
require 'json'

require 'log4r'
include Log4r

require 'em-synchrony/em-http'
require 'em-synchrony'
require 'cgi'

require 'digest/md5'

require 'pp'
require_relative 'es.rb'

class Board
  include HTTParty
  
  attr_reader :name, :getURL, :postURL, :postParameter
  
   #format :xml
  parser(
         Proc.new do |body,format|
           Nokogiri::XML(body)
         end
         )

  def initialize(name, getURL, postURL, postParameter, lastid)
    log = Log4r::Logger['olccs']
    @getURL = getURL
    @postURL = postURL
    @name = name
    @lastid = lastid
    @postParameter = postParameter

    lastorig = self.class.get(@getURL).xpath('/board/post[position()=1]/@id').to_s.to_i
    
    b = backend(1)
    if JSON.parse(b)['hits'] != nil
      lastlocal = JSON.parse(b)['hits']['hits'][0]['_source']['id']
      @last = lastlocal 
    else
      @last = lastorig-200
    end

    log.info "Board #{@name} initialized, last origin= #{lastorig}, last local= #{lastlocal}, last= #{@last}"
  end

  def backend(last=0, s=150)
    log = Log4r::Logger['olccs']
    log.debug "##~~BEGIN BACKEND ~~##"
    log.debug "last => {#{last}}"
    q = {
      "query" => {
        "range" => {
          "id" => { 
            "from" => last
          }
        }
      },
      "sort" => [
                 {"id" => {:reverse => true}}
                ],
      "size" => s
    }
    log.debug q.to_json
    log.debug "##~~END BACKEND ~~##"
    r = ES.new.query(@name,q.to_json)
    r
  end

  def search(query, s=150)
    log = Log4r::Logger['olccs']
    q = {
      "query" => {
        "query_string" => {
          "default_field" => "message",
          "default_operator" => "AND",
          "query" => query
        }
      },
      "sort" => [
                 {"id" => {:reverse => true}}
                ],

      "size" => s
    }

    r = ES.new.query(@name, q.to_json)
    begin
      @posts = JSON.parse(r)['hits']['hits']
    rescue
      log.error "search fucked for #{@name}"
      @posts = {}
    end
    builder = Nokogiri::XML::Builder.new do |xml|
      xml.board(:site => @name) {
        @posts.each { |p|
          i = p['_source']
          xml.post(:id => i['id'], :time => i['time']) {
            xml.info {
              xml.text i['info']
            }
            xml.login {
              xml.text i['login']
            }
            xml.message {
              xml.text i['message']
            }
          }
        }
      }
    end
    return builder.to_xml

  end

  def json(last=0)
    backend(last)
  end

  def xml(last=0)
    log = Log4r::Logger['olccs']
    begin
      @posts = JSON.parse(backend(last))['hits']['hits']
    rescue
      log.error "backend fucked up: #{last} for #{@name}"
      @posts = {}
    end
    builder = Nokogiri::XML::Builder.new do |xml|
      xml.board(:site => @name) {
        @posts.each { |p|
          i = p['_source']
          xml.post(:id => i['id'], :time => i['time']) {
            xml.info {
              xml.text i['info']
            }
            xml.login {
              xml.text i['login']
            }
            xml.message {
              xml.text i['message']
            }
          }
        }
      }
    end
    return builder.to_xml
  end

  def historique(from, to)
    q = {
      "query" => {
        "range" => {
          "time" => { 
            "from" => from,
            "to" => to
          }
        }
      },
      "sort" => [
                 {"id" => {:reverse => true}}
                ],
      "size" => 86400
    }
    
    ES.new.query(@name, q.to_json)
  end

  def histogramme
    q = {
      "query" => {
        "match_all" => {}
      },
      "size" => 0,
      "facets" => {
        "time" => {
          "date_histogram" => {
            "field"=> "time",
            "interval"=> "hour"
          }
        }
      }
    }
    #puts q.to_json
    ES.new.query(@name, q.to_json)
  end

  def stats
    q = {
      "query" => {
        "match_all" => {}
      },
      "size" => 0,
      "facets" => {
        "logins" => {
          "terms" => {
            "field" => "login",
            "size" => 20
          }
        }
      }
    }
    #puts q.to_json
    ES.new.query(@name, q.to_json)
  end
  
  def post(cookies, ua, content, request)
    log = Log4r::Logger['olccs']
    log.debug "##~~ BEGIN POST #{@name} ~~##"

    url = @postURL
    c = content.gsub('#{plus}#','+').gsub('#{amp}#','&').gsub('#{dcomma}#',';').gsub('#{percent}#','%')
    i = c.index("=") || -1

    if c[i+1,7] == "/olccs "
      c = @postParameter + '=' + command(c[i+8..-1], request)
    end

    b = {
      :body => { @postParameter.to_sym => c[i+1..-1]},
      :head => {
        "Referer" => @postURL,
        "Cookie" => cookies,
        "User-Agent" => ua}
    }
    r = EventMachine::HttpRequest.new("#{@postURL}").post(b)
    log.info r.response_header.status
    index
    log.debug "##~~ END POST #{@name} ~~##"
    return "Hello plop"
  end
  
    
  def index
    log = Log4r::Logger['olccs']
    log.debug "##~~ BEGIN INDEX ~~##"
    posts = []
    last_before = @last

    r = EventMachine::HttpRequest.new("#{@getURL}").get({ :query => {@lastid.to_sym => @last}}).response
    response = Nokogiri::XML(Hpricot.XML(r).to_s)

    response.xpath('/board/post').each do |p|
      pid = p.xpath("@id").to_s.to_i
      if pid > last_before then
        
        message_node = p.xpath("message")[0]
        cdata, text, autre = false, false, false
        message_node.children.each do |n|
          if n.class == Nokogiri::XML::CDATA
            cdata = true
            break;
          elsif n.class == Nokogiri::XML::Text
            text = true
          elsif n.class == Nokogiri::XML::Element
            autre = true
            break;
          end
        end
        #puts cdata, text, autre
        if autre then
          log.debug "AUTRE TRUC"
          content = message_node.inner_html
        else
          log.debug  "CDATA or TEXT"
          content = message_node.children[0].text
        end
          
        log.debug content
        # puts "#{pid} mis en boucle"
        @last = pid if pid > @last
        posts <<  Post.new(@name,
                           p.xpath("@id").to_s.to_i,
                           p.xpath("@time").to_s,
                           p.xpath("info").text,
                           p.xpath("login").text,
                           content
                           )
      end
    end

    if !posts.nil? and posts.size > 0 then
      log.debug "== #{@name} ==> #{posts.size}"
    end
    log.debug "##~~ END INDEX ~~##"
    ES.new.index(@name,posts)
  end
  
  def command(cmd, request)
    if cmd[0..7] == "weather" then
      # IP address to send to the Quova service
      ip_address = request.ip

      # API location
      mPRODUCTION_ENDPOINT = 'api.quova.com'
      mPRODUCTION_PORT = 80

      # Your credentials
      mAPI_KEY = '100.58dpqz32zwt5yt49wm8a'
      mSHARED_SECRET = 'VMH3YgWn'
      mAPI_VERSION = 'v1'

      current_time = Time.now
      timestamp = Time.now.to_i.to_s
      sig = Digest::MD5.hexdigest( mAPI_KEY+mSHARED_SECRET+timestamp )

      request_url = "/#{mAPI_VERSION}/ipinfo/#{ip_address}?apikey=#{mAPI_KEY}&sig=#{sig}&format=json"

      quova = EventMachine::HttpRequest.new("http://#{mPRODUCTION_ENDPOINT}#{request_url}").get
      r = JSON.parse(quova.response)
      ville = r['ipinfo']['Location']['CityData']['city']
      cp = r['ipinfo']['Location']['CityData']['postal_code']
      pays = r['ipinfo']['Location']['CountryData']['country']
      infos = CGI.escape("#{cp} #{ville} #{pays}")

      request_url = "http://where.yahooapis.com/v1/places.q(#{infos})?appid=mwrJjKXV34HMz2t2OGPu9LNEZicvik4Ics.zk9SfwfMvPoEqD2m46eCI3ooELrj3Qoux_cw-"
      yahoo_geoplace = EventMachine::HttpRequest.new("#{request_url}").get

      xml = Nokogiri::XML(yahoo_geoplace.response)
      woeid = xml.css("woeid")[0].content

      request_url = "http://weather.yahooapis.com/forecastrss?u=c&w=#{woeid}"
      yahoo_weather = EventMachine::HttpRequest.new("#{request_url}").get

      #puts yahoo_weather.response
      xml = Nokogiri::XML(yahoo_weather.response)
      
      city = xml.css("yweather|location")[0]["city"]
      conditions = xml.css("yweather|condition")[0]
      c_text = conditions["text"]
      c_temp = conditions["temp"]
      c_date = conditions["date"]

      forecast1 = xml.css("yweather|forecast")[0]
      f1_text = forecast1["text"]
      f1_min = forecast1["low"]
      f1_max = forecast1["high"]
      f1_date = forecast1["date"]

      
    end
    return "Météo pour: <b>#{city}</b>: #{c_text}, #{c_temp}°C // Prévisions pour demain: #{f1_text}, #{f1_min}°C / #{f1_max}°C"
  end

end
