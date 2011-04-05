require 'rubygems'
require 'httparty'
require 'nokogiri'
require 'json'

require 'log4r'
include Log4r

require 'em-synchrony/em-http'
require 'em-synchrony'

require 'pp'
require_relative 'es.rb'

class Board
  include HTTParty
  
  attr_reader :name, :getURL, :postURL
  
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

  def backend(s=150)
    log = Log4r::Logger['olccs']
    log.debug "##~~BEGIN BACKEND ~~##"
    q = {
      "query" => {
        "match_all" => {}
      },
      "sort" => [
                 {"id" => {:reverse => true}}
                ],
      :size => s
    }.to_json
    log.debug q
    log.debug "##~~END BACKEND ~~##"
    r = ES.new.query(@name,q)
    r
  end

  def xml
    @posts = JSON.parse(backend)['hits']['hits']
    builder = Nokogiri::XML::Builder.new do |xml|
      xml.board(:site => "test") {
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


  def post(cookies, ua, content)
    log = Log4r::Logger['olccs']
    log.debug "##~~ BEGIN POST #{@name} ~~##"

    url = @postURL
    c = content.gsub('#{plus}#','+').gsub('#{amp}#','&').gsub('#{dcomma}#',';').gsub('#{percent}#','%')
    b = {
      :body => { @postParameter.to_sym => c[c.index("=")+1..-1]},
      :head => {
        "Referer" => @postURL,
        "Cookie" => cookies,
        "User-Agent" => ua}
    }
    r = EventMachine::HttpRequest.new("#{@postURL}").post(b)
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
    response = Nokogiri::XML(r)

    response.xpath('/board/post').each do |p|
      pid = p.xpath("@id").to_s.to_i
      if pid > last_before then
        # puts "#{pid} mis en boucle"
        @last = pid if pid > @last
        posts <<  Post.new(@name,
                           p.xpath("@id").to_s.to_i,
                           p.xpath("@time").to_s,
                           p.xpath("info").text,
                           p.xpath("login").text,
                           p.xpath("message").text
                           )
      end
    end

    if !posts.nil? and posts.size > 0 then
      log.debug "== #{@name} ==> #{posts.size}"
    end
    log.debug "##~~ END INDEX ~~##"
    ES.new.index(@name,posts)
  end
end
