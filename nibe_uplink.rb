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
    response = @oauth.get(uri)
    raise AuthorizationError, response.body if response.is_a? Net::HTTPUnauthorized
    raise RateLimitError if response.is_a? Net::HTTPTooManyRequests 
    raise ServerError if response.is_a? Net::HTTPServerError
    response.body
  end

  # List all systems connected to the account
  def systems
    response = @oauth.get(API_ENDPOINT)
    raise AuthorizationError, response.body if response.is_a? Net::HTTPUnauthorized
    raise RateLimitError if response.is_a? Net::HTTPTooManyRequests 
    raise ServerError if response.is_a? Net::HTTPServerError
    response.body
  end

  # Get system status. Returns which subsystems are currently active
  def status
    return false unless @system_id
    uri = "#{API_ENDPOINT}/#{@system_id}/status/system"
    response = @oauth.get(uri)
    raise AuthorizationError, response.body if response.is_a? Net::HTTPUnauthorized
    raise RateLimitError if response.is_a? Net::HTTPTooManyRequests 
    raise ServerError if response.is_a? Net::HTTPServerError
    response.body
  end

  # Get info on installed software and software updates
  def software
    return false unless @system_id
    uri = "#{API_ENDPOINT}/#{@system_id}/software"
    response = @oauth.get(uri)
    raise AuthorizationError, response.body if response.is_a? Net::HTTPUnauthorized
    raise RateLimitError if response.is_a? Net::HTTPTooManyRequests 
    raise ServerError if response.is_a? Net::HTTPServerError
    response.body
  end

  # Get info and current values of the requested parameters,
  # or set parameters if a hash is provided as argument
  def parameters(parameters)
    return false unless @system_id
    uri = "#{API_ENDPOINT}/#{@system_id}/parameters"
    response = nil
    if parameters.is_a?(Hash)
      body = { settings: parameters }
      extheader = { 'content-type' => 'application/json' }
      response = @oauth.put(uri, body.to_json, extheader)
    else
      response = @oauth.get(uri, 'parameterIds' => parameters)
    end
    raise AuthorizationError, response.body if response.is_a? Net::HTTPUnauthorized
    raise RateLimitError if response.is_a? Net::HTTPTooManyRequests 
    raise ServerError if response.is_a? Net::HTTPServerError
    response.body
  end

  # Get notifications/alarms registered on the system
  def notifications
    return false unless @system_id
    uri = "#{API_ENDPOINT}/#{@system_id}/notifications"
    response = @oauth.get(uri)
    raise AuthorizationError, response.body if response.is_a? Net::HTTPUnauthorized
    raise RateLimitError if response.is_a? Net::HTTPTooManyRequests 
    raise ServerError if response.is_a? Net::HTTPServerError
    response.body
  end

  # Get info on the system. If arg is set to true it returns parameters for all systems,
  # if set to a valid category, returns info on only that category
  def serviceinfo(arg = false)
    return false unless @system_id
    uri = "#{API_ENDPOINT}/#{@system_id}/serviceinfo/categories"
    uri += "/#{arg}" if arg.is_a? String
    query = { 'parameters' => true } if arg && !arg.is_a?(String)
    response = @oauth.get(uri, query)
    raise AuthorizationError, response.body if response.is_a? Net::HTTPUnauthorized
    raise RateLimitError if response.is_a? Net::HTTPTooManyRequests 
    raise ServerError if response.is_a? Net::HTTPServerError
    response.body
  end

  # Get or set the smarthome mode
  def mode(mode = nil)
    return false unless @system_id
    uri = "#{API_ENDPOINT}/#{@system_id}/smarthome/mode"
    response = nil
    if mode
      body = { mode: mode }
      extheader = { 'content-type' => 'application/json' }
      response = @oauth.put(uri, body.to_json, extheader)
    else
      response = @oauth.get(uri)
    end
    raise AuthorizationError, response.body if response.is_a? Net::HTTPUnauthorized
    raise RateLimitError if response.is_a? Net::HTTPTooManyRequests 
    raise ServerError if response.is_a? Net::HTTPServerError
    response.body
  end

  # Get all registered smart home thermostats if no arguments are passed,
  # or create/update a smart home thermostat with the provided values
  def thermostats(values = {})
    return false unless @system_id
    uri = "#{API_ENDPOINT}/#{@system_id}/smarthome/thermostats"
    response = nil
    if values.empty?
      response = @oauth.get(uri)
    else
      raise ArgumentError, '`values` must contain externalId and name' if values['externalId'].nil? || values['name'].nil?
      extheader = { 'content-type' => 'application/json' }
      response = @oauth.post(uri, values.to_json, extheader)
      return response.message
    end
    raise AuthorizationError, response.body if response.is_a? Net::HTTPUnauthorized
    raise RateLimitError if response.is_a? Net::HTTPTooManyRequests 
    raise ServerError if response.is_a? Net::HTTPServerError
    response.body
  end
end
