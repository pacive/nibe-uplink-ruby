# nibe_uplink.rb
require 'json'
require 'yaml'
require_relative 'oauth'

# Class for interfacing with Nibe Uplink
class NibeUplink
  BASE_URL = 'https://api.nibeuplink.com'.freeze
  TOKEN_ENDPOINT = '/oauth/token'.freeze
  API_ENDPOINT = '/api/v1/systems'.freeze

  attr_accessor :system_id

  def initialize(client_id, client_secret, system_id = nil)
    @system_id = system_id
    @oauth = OAuth.new(
      BASE_URL,
      TOKEN_ENDPOINT,
      client_id,
      client_secret
    )
  end

  def authorize(auth_code, callback_url, permissions = 'r')
    scope = case permissions.downcase
            when 'rw' then 'READSYSTEM+WRITESYSTEM'
            when 'w' then 'WRITESYSTEM'
            else 'READSYSTEM'
            end

    @oauth.authorize(auth_code, callback_url, scope)
  end

  def system
    return false unless @system_id
    uri = "#{API_ENDPOINT}/#{@system_id}"
    response = @oauth.get(uri).body
    JSON.parse(response)
  end

  def systems
    uri = "#{API_ENDPOINT}"
    response = @oauth.get(uri).body
    JSON.parse(response)
  end

  def parameters(parameters)
    return false unless @system_id
    uri = "#{API_ENDPOINT}/#{@system_id}/parameters"
    response = @oauth.get(uri, 'parameterIds' => parameters).body
    JSON.parse(response)
  end

  def notifications
    return false unless @system_id
    uri = "#{API_ENDPOINT}/#{@system_id}/notifications"
    response = @oauth.get(uri).body
    JSON.parse(response)
  end

  def serviceinfo(arg = false)
    return false unless @system_id
    uri = "#{API_ENDPOINT}/#{@system_id}/serviceinfo/categories"
    uri += "/#{arg}" if arg.is_a? String
    query = { 'parameters' => true } if arg && !arg.is_a?(String)
    response = @oauth.get(uri, query).body
    JSON.parse(response)
  end
end
