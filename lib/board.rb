require 'rubygems'
require 'httparty'
require 'nokogiri'
require 'json'


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

    puts "Board #{@name} initialized, last origin= #{lastorig}, last local= #{lastlocal}, last= #{@last}"
  end

  def backend(s=10)
    puts "~~~~~~~~~~~~~~~~~~~~~~~~~##~~BEGIN BACKEND ~~##~~~~~~~~~~~~~~~~~~~~~~~~~~"
    q = {
      "query" => {
        "match_all" => {}
      },
      "sort" => [
                 {"id" => {:reverse => true}}
                ],
      :size => s
    }.to_json
    puts q
    puts "~~~~~~~~~~~~~~~~~~~~~~~~~##~~END BACKEND ~~##~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
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
    puts "{{{{{{{{{{{{{{{{{{{{{{{{{{{ BEGIN POST #{@name} }}}}}}}}}}}}}}}}}}}}}}}}}}}"
    t = Time.new
    puts "1 #{Time.new-t}"
    url = @postURL
    puts "2 #{Time.new-t}"
    b = {
      :body => { @postParameter.to_sym => content.rpartition('=')[2]},
      :head => {
        "Referer" => @postURL,
        "Cookie" => cookies,
        "User-Agent" => ua}
    }
    puts "3  #{Time.new-t} => #{@postURL}"
    #r = self.class.post(@postURL, b)
    r = EventMachine::HttpRequest.new("#{@postURL}").post(b)
    puts "4 #{Time.new-t}"
    pp r
    puts "5 #{Time.new-t}"
    index
    #sleep 2
    puts "6 #{Time.new-t}"
    puts "{{{{{{{{{{{{{{{{{{{{{{{{{{{ END POST #{@name} }}}}}}}}}}}}}}}}}}}}}}}}}}}"
    return "Hello plop"
  end
    
  def index
    puts "################# BEGIN INDEX #######################"
    posts = []
    last_before = @last
    t1 = Time.new
    r = EventMachine::HttpRequest.new("#{@getURL}").get.response
        response = Nokogiri::XML(r)
    # { :query => {@lastid.to_sym => @last}}
    puts "#{name} => #{Time.new - t1}, #{getURL}"
    
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
      puts "=================================== #{@name} ====================> #{posts.size}"
    end
    puts "################# END INDEX #######################"
    ES.new.index(@name,posts)
  end
end
