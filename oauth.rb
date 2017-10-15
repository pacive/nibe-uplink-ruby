# oauth.rb
require 'httpclient'
require 'json'
require 'digest'
require_relative 'token'

# A class for handling the OAuth protocol
class OAuth
  def initialize(base_url, token_endpoint, client_id, client_secret)
    @base_url = base_url
    @token_endpoint = token_endpoint
    @client_id = client_id
    @client_secret = client_secret
    @http = HTTPClient.new
    @file_name = ".oauth_token_#{Digest::MD5.hexdigest(@base_url)}"
    load_token if File.exist?("./#{@file_name}")
  end

# Send authorization code to get a token for the first time
  def authorize(authorization_code, callback_url, scope)
    post_body = {
      'grant_type' => 'authorization_code',
      'client_id' => @client_id,
      'client_secret' => @client_secret,
      'code' => authorization_code,
      'redirect_uri' => callback_url,
      'scope' => scope
    }

    response = JSON.parse(@http.post(@base_url + @token_endpoint, post_body).body)

    @token = Token.new(
      response['access_token'],
      response['expires_in'],
      response['refresh_token']
    )
    save_token
  rescue StandardError => e
    puts 'Unable to authorize'
    puts e.message
  end

# Sent a Http GET request to path, using token as authorization
  def get(path, parameters = nil, extheader = {})
    load_token unless @token

    header = { 'Authorization' => "Bearer #{@token.access_token}" }.merge(extheader)

    @http.get(@base_url + path, parameters, header)
  end

# Send a Http POST request to path, using token as authorization
  def post(path, parameters = '', extheader = {})
    load_token unless @token

    header = { 'Authorization' => "Bearer #{@token.access_token}" }.merge(extheader)

    @http.post(@base_url + path, parameters, header)
  end

# Send a Http PUT request to path, using token as authorization
def put(path, parameters = '', extheader = {})
    load_token unless @token

    header = { 'Authorization' => "Bearer #{@token.access_token}" }.merge(extheader)

    @http.put(@base_url + path, parameters, header)
  end

  private

# Load token from file and renew it if it has expired
  def load_token
    data = File.read("./#{@file_name}")
    @token = decrypt_token(data)

    refresh_token if @token.expired?
  rescue StandardError => e
    puts 'Error loading token'
    puts e.message
  end

# Save token to file
  def save_token
    data = encrypt_token
    File.write("./#{@file_name}", data)
    File.chmod(0o0600, "./#{@file_name}")
  end

# Request a new token using the refresh token
  def refresh_token
    postdata = {
      'grant_type' => 'refresh_token',
      'client_id' => @client_id,
      'client_secret' => @client_secret,
      'refresh_token' => @token.refresh_token
    }

    response = JSON.parse(@http.post(@base_url + @token_endpoint, postdata).body)

    @token.refresh!(response['access_token'], response['expires_in'], response['refresh_token'])
    save_token
  rescue StandardError => e
    puts 'Unable to refresh token'
    puts e.message
  end

# Encrypt a string representation of the token
  def encrypt_token
    string = @token.to_json
    cipher = OpenSSL::Cipher::AES.new(128, :CBC)
    cipher.encrypt
    cipher.key = @client_secret
    cipher.iv = @client_id
    cipher.update(string) + cipher.final
  end

# Decrypt an encrypted token
  def decrypt_token(data)
    cipher = OpenSSL::Cipher::AES.new(128, :CBC)
    cipher.decrypt
    cipher.key = @client_secret
    cipher.iv = @client_id
    json = cipher.update(data) + cipher.final
    t = JSON.parse(json)
    Token.new(t['access_token'], t['expires_in'], t['refresh_token'], t['token_type'], Time.at(t['timestamp']))
  end
end
