# frozen_string_literal: true

require 'optparse'
require 'json'
require 'yaml'
require 'logger'
require_relative 'nibe_uplink'
require_relative 'nibe_uplink_helper'
require_relative 'user_interaction'

# Interface with the Nibe uplink service
class NibeUplinkInterface
  def initialize(uplink = nil)
    @logger = Logger.new('nibe_uplink.log', 2, 1_048_576)
    if uplink
      @nu = uplink
      @options = { query: nil, parameters: nil, values: nil }
    else
      authorize
    end
  end

  def parse(args)
    optparser = OptionParser.new do |opts|
      opts.banner = 'Usage: nu.rb [-a|p|s|l|n|i|m|t|a|o|h] [ARGS] [-v ARGS]'

      opts.on('--authorize', 'Start authorization wizard') { @options[:query] = :authorize }

      opts.on('-p', '--parameters PARAMETERS', Array, 'Get values for the specified parameters') do |parameters|
        @options[:query] = :parameters
        @options[:parameters] = parameters
      end

      opts.on('-s', '--system', 'Get info on the current system') { @options[:query] = :system }

      opts.on('-l', '--systems', 'List all connected systems') { @options[:query] = :systems }

      opts.on('-n', '--notifications', 'Get active alarms on system') { @options[:query] = :notifications }

      opts.on('-i', '--serviceinfo [ARG]',
              'Get info on the system.',
              'If arg is set to true it returns parameters for all systems,',
              'if set to a valid category, returns info on only that category') do |arg|
        @options[:query] = :serviceinfo
        @options[:parameters] = arg
      end

      opts.on('-m', '--mode [MODE]', %I[home away vacation], 'Gets the smart home mode') do |arg|
        @options[:query] = :mode
        @options[:parameters] = arg
      end

      opts.on('-t', '--thermostats [ARGS]', Array, 'Get all smart home thermostats') do |arg|
        @options[:query] = :thermostats
        @options[:parameters] = arg
      end

      opts.on('-a', '--status', 'Get system status.', 'Returns which subsystems are currently active') { @options[:query] = :status }

      opts.on('-o', '--software', 'Get info on installed software and software updates') { @options[:query] = :software }

      opts.on('-v', '--values VALUES', Array, 'List of values to retreive') { |values| @options[:values] = values }

      opts.on_tail('-h', '--help', 'Display this help') do
        puts opts
        exit
      end
    end

    optparser.parse!(args)
    @options[:query] ? send(@options[:query]) : parse(['-h'])
  end

  private

  def authorize
    config = {}
    config[:client_id] = UI.input('Client id:')
    config[:client_secret] = UI.input('Client secret:')
    callback_url = UI.input('Callback URL:')
    puts 'Copy the following URL and paste into your browser and follow the instructions:'
    puts "https://api.nibeuplink.com/oauth/authorize?response_type=code&client_id=#{config[:client_id]}" \
        "&scope=READSYSTEM+WRITESYSTEM&redirect_uri=#{callback_url}&state=STATE"
    authorization_code = UI.input('Copy the returned authorization code and paste it here:')
    @nu = NibeUplink.new(config[:client_id], config[:client_secret])
    @nu.authorize(authorization_code, callback_url)
    sys = JSON.parse(@nu.systems)
    if sys['numItems'] != 1
      config[:system_id] = systems['objects'][0]['systemId']
    else
      puts 'Select default system:'
      NibeUplinkHelper.list_systems
      config[:system_id] = UI.input('System ID:')
    end
    @nu.system_id = config[:system_id]
    File.write('/etc/nibe_uplink.conf', config.to_yaml)
    puts 'Authorization completed!'
  end

  def parameters
    response = []
    set = NibeUplinkHelper.extract_set_parameters(@options[:parameters])
    response.concat JSON.parse(@nu.parameters(set)) unless set.empty?
    unless @options[:parameters].empty?
      if @options[:parameters].length > 15
        NibeUplinkHelper.split_parameter_array(@options[:parameters]).each do |a|
          response.concat JSON.parse(@nu.parameters(a))
        end
      else
        response.concat JSON.parse(@nu.parameters(@options[:parameters]))
      end
    end
    @options[:values] ? NibeUplinkHelper.get_parameter_values(response, @options[:values]).to_json : response.to_json
  rescue IOError => e
    @logger.error "Error:\n#{e.message}"
  end

  def system
    @options[:values] ? NibeUplinkHelper.get_values(@nu.system, @options[:values]).to_json : @nu.system
  rescue IOError => e
    @logger.error "Error:\n#{e.message}"
  end

  def systems
    @options[:values] ? NibeUplinkHelper.get_values(@nu.systems, @options[:values]).to_json : @nu.systems
  rescue IOError => e
    @logger.error "Error:\n#{e.message}"
  end

  def notifications
    @options[:values] ? NibeUplinkHelper.get_values(@nu.notifications, @options[:values]).to_json : @nu.notifications
  rescue IOError => e
    @logger.error "Error:\n#{e.message}"
  end

  def serviceinfo
    @options[:parameters] = true if @options[:parameters] == 'true'
    if @options[:values]
      NibeUplinkHelper.get_values(@nu.serviceinfo(@options[:parameters]), @options[:values]).to_json
    else
      @nu.serviceinfo(@options[:parameters])
    end
  rescue IOError => e
    @logger.error "Error:\n#{e.message}"
  end

  def mode
    case @options[:parameters]
    when :home
      return @nu.home_mode('DEFAULT_OPERATION')
    when :away
      return @nu.home_mode('AWAY_FROM_HOME')
    when :vacation
      return @nu.home_mode('VACATION')
    end
    @nu.home_mode
  rescue IOError => e
    @logger.error "Error:\n#{e.message}"
  end

  def thermostats
    if @options[:parameters]
      par = {}
      @options[:parameters].each do |s|
        arr = s.split('=')
        par[arr[0].to_sym] = arr[0] == 'climateSystems' ? [arr[1]] : arr[1]
      end
      return @nu.thermostats(par)
    end
    options[:values] ? NibeUplinkHelper.get_values(@nu.thermostats, @options[:values]).to_json : @nu.thermostats
  rescue IOError => e
    @logger.error "Error:\n#{e.message}"
  end

  def status
    NibeUplinkHelper.get_status_items(@nu.status)
  rescue IOError => e
    @logger.error "Error:\n#{e.message}"
  end

  def software
    @options[:values] ? NibeUplinkHelper.get_values(@nu.software, @options[:values]).to_json : @nu.software
  rescue IOError => e
    @logger.error "Error:\n#{e.message}"
  end
end

nu = nil
if File.exist?('./nibe_uplink.conf')
  config = YAML.load_file('./nibe_uplink.conf')
  nu = NibeUplink.new(config[:client_id], config[:client_secret], config[:system_id])
end
nui = NibeUplinkInterface.new(nu)
puts nui.parse(ARGV)
