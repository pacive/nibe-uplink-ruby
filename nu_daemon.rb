# nu_daemon.rb
# frozen_string_literal: true

require 'json'
require 'yaml'
require 'logger'
require 'mqtt'
require_relative 'nibe_uplink'
require_relative 'nibe_uplink_parser'

class NibeUplinkDaemon
  include NibeUplinkParser

  attr_accessor :log, :interval

  def initialize(config_file)
    @config_file = config_file
    @config = YAML.load_file(@config_file)
    @uplink = NibeUplink.new(@config[:client_id], @config[:client_secret], @config[:system_id])
    @parameters = split_parameters(@config[:parameters])
    @log = Logger.new($stdout, level: Logger::INFO, progname: 'NibeUplink')
    @interval = 60
    @mqtt = MQTT::Client.new(host: @config[:mqtt_host],
                             username: @config[:mqtt_username],
                             password: @config[:mqtt_password],
                             client_id: 'Nibeuplink')
    @mqtt.connect
  rescue StandardError => e
    @log.error "Exception occurred: #{e.inspect}"
    reconnect_mqtt
  rescue MQTT::Exception => e
    @log.error "Exception occurred: #{e.inspect}"
    reconnect_mqtt
  end

  def run!
    @log.info 'Starting Nibe uplink connection...'
    listener = Thread.new { listen }
    work
  rescue SignalException
    @log.warn 'Terminating...'
    @log.debug { 'Waiting for threads...' }
    sleep 0.01 while Thread.list.size > 3
    @log.debug { 'Stopping listener...' }
    listener.exit
    @log.debug { 'Disconnecting from MQTT...' }
    @mqtt.disconnect
    @log.debug { 'Exiting!' }
    Kernel.exit
  end

  private

  def work
    loop do
      start_time = Time.now
      reload_config if config_changed?
      @parameters.each do |a|
        Thread.new { parameters(a) }
        sleep 5
      end
      Thread.new { status }
      sleep 5
      Thread.new { system }
      sleep(start_time + @interval - Time.now)
      if Time.now - Time.new(start_time.year, start_time.month, start_time.day) < @interval * 2
        Thread.new { software }
        sleep 5
      end
    rescue StandardError => e
      @log.error "Exception occurred:\n#{e.inspect}"
      next
    rescue MQTT::Exception => e
      @log.error "MQTT Exception in work:\n#{e.inspect}"
      reconnect_mqtt
      next
    end
  end

  def listen
    @mqtt.subscribe('Nibeuplink/Set/#')
    @mqtt.get do |topic, message|
      command = parse_mqtt(topic, message)
      @log.info { "Setting #{command[0]}: #{command[1]}" } unless command[0] == :thermostats
      @uplink.send(*command)
    rescue StandardError => e
      @log.error "Exception occurred:\n#{e.inspect}"
      next
    rescue MQTT::Exception => e
      @log.error "MQTT Exception in listener:\n#{e.inspect}"
      reconnect_mqtt
      next
    end
  end

  def config_changed?
    Time.now - File.mtime(@config_file) < @interval * 1.5
  end

  def reload_config
    @log.info 'Config changed, reloading...'
    @config = YAML.load_file(@config_file)
    @parameters = split_parameters(@config[:parameters])
    return if @mqtt.username == @config[:mqtt_username] &&
              @mqtt.password == @config[:mqtt_password] &&
              @mqtt.host == @config[:mqtt_host]

    @log.info 'MQTT credentials changed, reconnecting...'
    @mqtt.disconnect if @mqtt.connected?
    @mqtt.host = @config[:mqtt_host]
    @mqtt.username = @config[:mqtt_username]
    @mqtt.password = @config[:mqtt_password]
    @mqtt.connect
  end

  def parameters(array)
    res = parse_parameters(@uplink.parameters(array))
    out = convert_parameters(res)
    @log.debug 'Got parameters from Nibe uplink, publishing to MQTT...'
    out.each do |k, v|
      @mqtt.publish("Nibeuplink/Parameters/#{k}", v)
    end
    @log.debug 'Done!'
  rescue ServerError => e
    @log.debug { e.inspect }
  rescue NibeUplinkError => e
    @log.warn { e.inspect }
  end

  def status
    out = parse_status(@uplink.status)
    @log.debug 'Got status from Nibe uplink, publishing to MQTT...'
    out.each do |k, v|
      @mqtt.publish("Nibeuplink/Status/#{k}", v)
    end
    @log.debug 'Done!'
  rescue ServerError => e
    @log.debug { e.inspect }
  rescue NibeUplinkError => e
    @log.warn { e.inspect }
  end

  def system
    out = parse_system(@uplink.system)
    @log.debug 'Got system info from Nibe uplink, publishing to MQTT...'
    out.each do |k, v|
      @mqtt.publish("Nibeuplink/System/#{k}", v)
    end
    @mqtt.publish('Nibeuplink/Service/Heartbeat', 'ON')
    @log.debug 'Done!'
  rescue ServerError => e
    @log.debug { e.inspect }
  rescue NibeUplinkError => e
    @log.warn { e.inspect }
  end

  def software
    @log.debug 'Checking for software upgrade...'
    upgrade = parse_software(@uplink.software)
    @mqtt.publish('Nibeuplink/Software', upgrade)
  rescue ServerError => e
    @log.debug { e.inspect }
  rescue NibeUplinkError => e
    @log.warn { e.inspect }
  end

  def reconnect_mqtt(init_timeout = 1)
    @log.info "MQTT connection lost, retrying in #{init_timeout}s"
    sleep init_timeout
    @mqtt.connect
    @log.info 'Reconnect successful'
  rescue StandardError
    (init_timeout * 2) < 60 ? reconnect_mqtt(init_timeout * 2) : reconnect_mqtt(60)
  rescue MQTT::Exception
    (init_timeout * 2) < 60 ? reconnect_mqtt(init_timeout * 2) : reconnect_mqtt(60)
  end
end

$stdout.sync = true
daemon = NibeUplinkDaemon.new('/home/openhabian/ruby/nibe_uplink/nibe_uplink.conf')
daemon.log.level = Logger::DEBUG if ARGV.include? '--debug'
daemon.interval = 20
daemon.run!
