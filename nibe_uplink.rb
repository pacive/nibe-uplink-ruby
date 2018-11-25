# nibe_uplink.rb
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'simpleoauth'

class NibeUplinkError < StandardError
end

class ServerError < NibeUplinkError
end

class AuthorizationError < NibeUplinkError
end

class RateLimitError < NibeUplinkError
end

# Class for interfacing with Nibe Uplink
class NibeUplink
  BASE_URL = 'https://api.nibeuplink.com'
  TOKEN_ENDPOINT = '/oauth/token'
  API_ENDPOINT = '/api/v1/systems'

  attr_accessor :system_id

  def initialize(client_id, client_secret, system_id = nil)
    @system_id = system_id
    @oauth = SimpleOAuth::Client.new(BASE_URL,
                                     TOKEN_ENDPOINT,
                                     client_id,
                                     client_secret)

    @oauth.load_token('/var/lib/misc/')
  end

  # Send authorization code to get a token for the first time
  def authorize(auth_code, callback_url, scope = 'READSYSTEM+WRITESYSTEM')
    @oauth.authorize(auth_code, callback_url, scope)
  end

  # Get info on the current system
  def system
    return false unless @system_id

    uri = "#{API_ENDPOINT}/#{@system_id}"
    request(:get, uri).body
  end

  # List all systems connected to the account
  def systems
    request(:get, API_ENDPOINT).body
  end

  # Get system status. Returns which subsystems are currently active
  def status
    return false unless @system_id

    uri = "#{API_ENDPOINT}/#{@system_id}/status/system"
    request(:get, uri).body
  end

  # Get info on installed software and software updates
  def software
    return false unless @system_id

    uri = "#{API_ENDPOINT}/#{@system_id}/software"
    request(:get, uri).body
  end

  # Get info and current values of the requested parameters,
  # or set parameters if a hash is provided as argument
  def parameters(parameters)
    return false unless @system_id

    uri = "#{API_ENDPOINT}/#{@system_id}/parameters"
    if parameters.is_a?(Hash)
      body = { settings: parameters }
      request(:put, uri, nil, body.to_json).body
    else
      request(:get, uri, 'parameterIds' => parameters).body
    end
  end

  # Get notifications/alarms registered on the system
  def notifications
    return false unless @system_id

    uri = "#{API_ENDPOINT}/#{@system_id}/notifications"
    request(:get, uri).body
  end

  # Get info on the system. If arg is set to true it returns parameters for all systems,
  # if set to a valid category, returns info on only that category
  def serviceinfo(arg = false)
    return false unless @system_id

    uri = "#{API_ENDPOINT}/#{@system_id}/serviceinfo/categories"
    uri += "/#{arg}" if arg.is_a? String
    query = { 'parameters' => true } if arg && !arg.is_a?(String)
    request(:get, uri, query).body
  end

  # Get or set the smarthome mode
  def mode(mode = nil)
    return false unless @system_id

    uri = "#{API_ENDPOINT}/#{@system_id}/smarthome/mode"
    if mode
      body = { mode: mode }
      request(:put, uri, nil, body.to_json).body
    else
      request(:get, uri).body
    end
  end

  # Get all registered smart home thermostats if no arguments are passed,
  # or create/update a smart home thermostat with the provided values
  def thermostats(values = {})
    return false unless @system_id

    uri = "#{API_ENDPOINT}/#{@system_id}/smarthome/thermostats"
    if values.empty?
      request(:get, uri).body
    else
      raise ArgumentError, '`values` must contain externalId and name' if values['externalId'].nil? || values['name'].nil?

      request(:post, uri, nil, values.to_json).message
    end
  end

  private

  def request(verb, uri, query = nil, body = nil)
    extheader = { 'accept' => 'application/json' }
    res = case verb
          when :get
            @oauth.get(uri, query, extheader)
          when :post, :put
            extheader['content-type'] = 'application/json'
            @oauth.send(verb, uri, body, extheader)
          end
    raise AuthorizationError, res.body if res.is_a? Net::HTTPUnauthorized
    raise RateLimitError if res.is_a? Net::HTTPTooManyRequests
    raise ServerError if res.is_a? Net::HTTPServerError

    res
  end
end
