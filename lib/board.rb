require 'rubygems'
require 'httparty'
require 'nokogiri'
require 'hpricot'
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
end
