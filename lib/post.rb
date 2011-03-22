class Post
  
  attr_reader :post_id

  def initialize(board, pid, time, info, login, message)
    @board = board.to_s.strip
    @post_id = pid
    @time = time.strip
    @info = info.strip
    @login = login.strip
    @message = message.strip
  end


  def to_json
    {
      'board' => @board,
      'id' => @post_id,
      'time' => @time,
      'info' => @info,
      'login' => @login,
      'message' => @message
    }.to_json
  end
end
