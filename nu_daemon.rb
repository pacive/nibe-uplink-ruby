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

  def initialize(config_file)
    @config_file = config_file
    @log = Logger.new($stdout, progname: 'NibeUplink', formatter: proc { |severity, _datetime, progname, msg|
      "#{severity} -- #{progname}: #{msg}\n"
    })
    load_config(@config_file)
    @uplink = NibeUplink.new(@config[:client_id], @config[:client_secret], @config[:system_id])
    @parameters = split_parameters(@config[:parameters])
    @mqtt = MQTT::Client.new(host: @config[:mqtt_host],
                             username: @config[:mqtt_username],
                             password: @config[:mqtt_password],
                             client_id: 'Nibeuplink')
  end

  def run!
    @log.info 'Starting Nibe uplink connection...'
    @mqtt.connect
    @listener = Thread.new { listen }
    work
  rescue Errno::EPIPE
    @listener.exit
    @mqtt.disconnect
    retry
  rescue StandardError, MQTT::Exception => e
    @log.error "Exception occurred: #{e.inspect}"
    reconnect_mqtt
  rescue SignalException => e
    graceful_shutdown
  end

  private

  def work
    @log.debug { 'Starting worker' }
    loop do
      start_time = Time.now
      reload_config if config_changed?
      @mqtt.connect unless @mqtt.connected?
      @parameters.each do |a|
        Thread.new { parameters(a) }
        sleep 5
      end
      Thread.new { status }
      sleep 5
      Thread.new { system }
      start_time + @config[:interval] > Time.now + 5 ? sleep(start_time + @config[:interval] - Time.now) : sleep(5)
      if Time.now - Time.new(start_time.year, start_time.month, start_time.day) < @config[:interval] * 2
        Thread.new { software }
        sleep 5
      end
    rescue MQTT::Exception, Errno::ECONNREFUSED, Errno::ECONNRESET => e
      @log.error "MQTT Exception in worker:\n#{e.inspect}"
      reconnect_mqtt
      next
    rescue StandardError => e
      @log.error "Exception in worker:\n#{e.inspect}\n#{e.backtrace_locations.join("\n")}"
      raise e if e.is_a? Errno::EPIPE

      next
    end
  end

  def listen
    @log.debug { 'Starting listener' }
    @mqtt.subscribe('Nibeuplink/Set/#')
    loop do
      sleep(1) until @mqtt.connected?
      topic, message = @mqtt.get
      command = parse_mqtt(topic, message)
      @log.debug { "Setting #{command[0]}: #{command[1]}" }
      @uplink.send(*command)
    rescue StandardError => e
      @log.error "Exception in listener:\n#{e.inspect}"
      next
    rescue MQTT::Exception => e
      @log.error "MQTT Exception in listener:\n#{e.inspect}"
      next
    end
  end

  def config_changed?
    Time.now - File.mtime(@config_file) < @config[:interval] * 1.5
  end

  def load_config(config_file)
    @config = YAML.load_file(config_file)
    @parameters = split_parameters(@config[:parameters])
    @log.level = @config[:log_level]
  end

  def reload_config
    @log.info 'Config changed, reloading...'
    load_config(@config_file)
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
    out.each do |k, v|
      @mqtt.publish("Nibeuplink/Parameters/#{k}", v)
    end
  rescue ServerError => e
    @log.debug { e.inspect }
  rescue NibeUplinkError => e
    @log.warn { e.inspect }
  end

  def status
    out = parse_status(@uplink.status)
    out.each do |k, v|
      @mqtt.publish("Nibeuplink/Status/#{k}", v)
    end
  rescue ServerError => e
    @log.debug { e.inspect }
  rescue NibeUplinkError => e
    @log.warn { e.inspect }
  end

  def system
    out = parse_system(@uplink.system)
    out.each do |k, v|
      @mqtt.publish("Nibeuplink/System/#{k}", v)
    end
    @mqtt.publish('Nibeuplink/Service/Heartbeat', 'ON')
  rescue ServerError => e
    @log.debug { e.inspect }
  rescue NibeUplinkError => e
    @log.warn { e.inspect }
  end

  def software
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
    @mqtt.subscribe('Nibeuplink/Set/#')
    @log.info 'Reconnect successful'
  rescue StandardError, MQTT::Exception
    (init_timeout * 2) < 60 ? reconnect_mqtt(init_timeout * 2) : reconnect_mqtt(60)
  end

  def graceful_shutdown
    @log.warn 'Terminating...'
    @log.debug { 'Waiting for threads...' }
    sleep 0.01 while Thread.list.size > 3
    @log.debug { 'Stopping listener...' }
    @listener.exit
    @log.debug { 'Disconnecting from MQTT...' }
    @mqtt.disconnect
    @log.debug { 'Exiting!' }
    Kernel.exit
  end
end

$stdout.sync = true
NibeUplinkDaemon.new(ARGV[0]).run!
