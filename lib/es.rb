require 'rubygems'
require 'httparty'
require 'singleton'
require 'json'

require 'em-synchrony/em-http'

class ES
  include HTTParty
  #include Singleton

  #debug_output
  format :json

  attr_writer :address

  def initialize
    @address = Settings.instance.es
  end

  def query(idx, q)
    EventMachine::HttpRequest.new("#{@address}/#{idx}/_search").post({ :body => q }).response
    #self.class.post("#{@address}/#{idx}/_search", {:body => q})
  end

  def query_all(q)
    self.class.post("#{@address}/_search", {:body => q})
  end

  def index(idx,posts)
    new = 0
    total = 0
    t1 = Time.new

    multi = EventMachine::Synchrony::Multi.new
      
    posts.each do |p|
      multi.add p.post_id, EventMachine::HttpRequest.new("#{@address}/#{idx}/post/#{p.post_id}").post({ :body => p.to_json, :query => { :op_type => "create" } })
    end

    res = multi.perform
    
    multi.responses[:callback].each_pair do |i,c|
      if c.response_header.status == 201 then
        new = new + 1
      end
    end
    
    if multi.responses[:errback].size != 0 then
      puts "ERROR"
    end

    total = multi.requests.size
        
    t2 = Time.new

    return [new,total,t2-t1]
  end

end

