require 'json'
# token.rb

# A class for storing and accessing instances of OAuth tokens
class Token
  attr_reader :access_token, :refresh_token

  def initialize(access_token, expires_in, refresh_token, token_type = 'bearer', timestamp = Time.now)
    @access_token = access_token
    @timestamp = timestamp
    @expires_in = expires_in
    @refresh_token = refresh_token
    @token_type = token_type
  end

  def refresh!(access_token, expires_in, refresh_token)
    @access_token = access_token
    @timestamp = Time.now
    @expires_in = expires_in
    @refresh_token = refresh_token
  end

  def expired?
    Time.now > @timestamp + @expires_in
  end

  def to_json
    hash = {
      access_token: @access_token,
      timestamp: @timestamp.to_i,
      expires_in: @expires_in,
      refresh_token: @refresh_token,
      token_type: @token_type
    }
    hash.to_json
  end
end
