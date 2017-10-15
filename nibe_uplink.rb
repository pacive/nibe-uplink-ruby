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

# Send authorization code to get a token for the first time
  def authorize(auth_code, callback_url, permissions = 'r')
    scope = case permissions.downcase
            when 'rw' then 'READSYSTEM+WRITESYSTEM'
            when 'w' then 'WRITESYSTEM'
            else 'READSYSTEM'
            end

    @oauth.authorize(auth_code, callback_url, scope)
  end

# Get info on the current system
  def system
    return false unless @system_id
    uri = "#{API_ENDPOINT}/#{@system_id}"
    @oauth.get(uri).body
  end

# List all systems connected to the account
  def systems
    uri = "#{API_ENDPOINT}"
    @oauth.get(uri).body
  end

# Get system status. Returns which subsystems are currently active
  def status
    return false unless @system_id
    uri = "#{API_ENDPOINT}/#{@system_id}/status/system"
    @oauth.get(uri).body
  end

# Get info on installed software and software updates
  def software
    return false unless @system_id
    uri = "#{API_ENDPOINT}/#{@system_id}/software"
    @oauth.get(uri).body
  end

# Get info and current values of the requested parameters
  def parameters(parameters)
    return false unless @system_id
    uri = "#{API_ENDPOINT}/#{@system_id}/parameters"
    @oauth.get(uri, 'parameterIds' => parameters).body
  end

# Set new values for settings
  def set_parameters(parameters = {})
    return false unless @system_id
    uri = "#{API_ENDPOINT}/#{@system_id}/parameters"

    body = {settings: parameters}
    extheader = {"content-type" => "application/json"}
    @oauth.put(uri, body.to_json, extheader).body
  end

# Get notifications/alarms registered on the system
  def notifications
    return false unless @system_id
    uri = "#{API_ENDPOINT}/#{@system_id}/notifications"
    @oauth.get(uri).body
  end

# Get info on the system. If arg is set to true it returns parameters for all systems,
# if set to a valid category, returns info on only that category
  def serviceinfo(arg = false)
    return false unless @system_id
    uri = "#{API_ENDPOINT}/#{@system_id}/serviceinfo/categories"
    uri += "/#{arg}" if arg.is_a? String
    query = { 'parameters' => true } if arg && !arg.is_a?(String)
    @oauth.get(uri, query).body
  end

# Get the smarthome mode
  def home_mode
    return false unless @system_id
    uri = "#{API_ENDPOINT}/#{@system_id}/smarthome/mode"
    @oauth.get(uri).body
  end

# Set the smart home mode
  def set_home_mode(mode)
    return false unless @system_id
    uri = "#{API_ENDPOINT}/#{@system_id}/smarthome/mode"
    body = {mode: mode}
    extheader = {"content-type" => "application/json"}
    @oauth.put(uri, body.to_json, extheader)
  end

# Get all registered smart home thermostats
  def thermostats
    return false unless @system_id
    uri = "#{API_ENDPOINT}/#{@system_id}/smarthome/thermostats"
    @oauth.get(uri).body
  end

# Create or update a smart home thermostat
  def set_thermostat(id, name, values = {})
    return false unless @system_id
    uri = "#{API_ENDPOINT}/#{@system_id}/smarthome/thermostats"
    body = {externalId: id, name: name}.merge(values)
    extheader = {"content-type" => "application/json"}
    @oauth.post(uri, body.to_json, extheader)
  end    
end
