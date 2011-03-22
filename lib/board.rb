require 'rubygems'
require 'httparty'
require 'nokogiri'
require 'json'

require 'em-synchrony/em-http'
require 'pp'
require_relative 'es.rb'

class Board
  include HTTParty
  
  attr_reader :name
  
   #format :xml
  parser(
         Proc.new do |body,format|
           Nokogiri::XML(body)
         end
         )

  def initialize(name, getURL, postURL)
    @getURL = getURL
    @postURL = postURL
    @name = name

    @cache_j = nil
    @cache_x = nil

    lastorig = self.class.get(@getURL).xpath('/board/post[position()=1]/@id').to_s.to_i
    
    if JSON.parse(backend(1))['hits'] != nil
      lastlocal = JSON.parse(backend(1))['hits']['hits'][0]['_source']['id']
      @last = lastlocal 
    else
      @last = lastorig-200
    end

    puts "Board #{@name} initialized, last origin= #{lastorig}, last local= #{lastlocal}, last= #{@last}"
  end

  def backend(s=150)
    if s==150 and @cache_j != nil then
      return @cache_j
    end
    q = {
      "query" => {
        "match_all" => {}
      },
      "sort" => [
                 {"id" => {:reverse => true}}
                ],
      :size => s
    }.to_json

    @cache_j = ES.new.query(@name,q)
    return @cache_j
        
  end

  def xml
    if @cache_x != nil then
      return @cache_x
    end
    @posts = JSON.parse(backend)['hits']['hits']
    builder = Nokogiri::XML::Builder.new do |xml|
      xml.boards(:site => "test") {
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
    @cache_x = builder.to_xml
    return @cache_x
  end


  def post(headers)
    url = 
  end

  def index
    posts = []
    last_before = @last
    t1 = Time.new
    response = Nokogiri::XML(EventMachine::HttpRequest.new("#{@getURL}").get({ :query => {:last => @last}}).response)
    puts "#{name} => #{Time.new - t1}"
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
      @cache_j = nil
      @cache_x = nil
    end
    ES.new.index(@name,posts)
  end
end
