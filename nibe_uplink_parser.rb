# nibe_uplink_parser.rb
# frozen_string_literal: true

module NibeUplinkParser
  def split_parameters(par)
    pages = (par.size - 1) / 15 + 1
    parameters = []

    pages.times do |i|
      remainder = par.size - (i * 15)
      parameters[i] = par.slice(i * 15, remainder < 15 ? remainder : 15)
    end
    parameters
  end

  def parse_parameters(json)
    hash = JSON.parse(json)
    result = {}
    hash.each { |h| result[h['parameterId']] = h['rawValue'] }
    result
  end

  def convert_parameters(hash)
    hash.update(hash) do |k, v|
      case k
      when 40004, 40067, 40013, 40014, 43136, 40050, 40032, 43009, 40047, 40048, 43008, 40007, 40129, 43005
        v / 10.0
      when 43084
        v / 100.0
      else
        v
      end
    end
    hash
  end

  def parse_status(json)
    hash = JSON.parse(json)
    result = {
      'Ventilation' => 'OFF',
      'Heating Medium Pump' => 'OFF',
      'Holiday' => 'OFF',
      'Hot Water' => 'OFF',
      'Compressor' => 'OFF',
      'Addition' => 'OFF',
      'Heating' => 'OFF'
    }
    hash.each { |h| result[h['title']] = 'ON' }
    result.transform_keys! { |k| k.delete(' ').capitalize }
  end

  def parse_system(json)
    hash = JSON.parse(json).select { |k| %w[lastActivityDate connectionStatus hasAlarmed].include? k }
    hash['Alarm'] = @uplink.notifications if hash['hasAlarmed']
    hash['hasAlarmed'] = hash['hasAlarmed'] ? 'ON' : 'OFF'
    hash['connectionStatus'] = case hash['connectionStatus']
                               when 'ONLINE' then 0
                               when 'PENDING' then 1
                               else 2
                               end
    hash['lastActivityDate'] = hash['lastActivityDate'].chop + '+0000'
    hash.transform_keys!(&:capitalize)
  end

  def parse_software(json)
    hash = JSON.parse(json)
    if hash['upgrade'].nil?
      'OFF'
    else
      @log.info "New software upgrade available: #{hash['upgrade']}"
      'ON'
    end
  end

  def parse_mqtt(topic, message)
    command = topic.split('/')
    command[0, 3] = command[2].downcase.to_sym
    command[1] = case command[0]
                 when :mode then message
                 when :parameters then { command[1].downcase.to_sym => message }
                 when :thermostats then JSON.parse(message)
                 else raise ArgumentError, 'Not a valid topic or message'
                 end
    command
  end

  def parse_parameter_response(response)
    hash = JSON.parse(response)
    { hash[0]['parameter']['parameterId'] => hash[0]['parameter']['rawValue'] }
  end
end
