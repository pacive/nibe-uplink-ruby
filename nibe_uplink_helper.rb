# frozen_string_literal: true

# A module with helper methods for Nibe Uplink
module NibeUplinkHelper
  def self.list_systems(systems)
    puts "ID:\tName:"
    systems['numItems'].times do |i|
      puts "#{systems['objects'][i]['systemId']}\t(#{systems['objects'][i]['name']})"
    end
  end

  def self.extract_set_parameters(array)
    parameters = {}
    temp_array = array.select { |str| str.include? '=' }
    array.reject! { |str| str.include? '=' }
    temp_array.each do |str|
      a = str.split('=')
      parameters[a[0].to_sym] = a[1]
    end
    parameters
  end

  def self.get_parameter_values(hash_array, values)
    result = {}
    if values.size > 1
      hash_array.each do |hash|
        r = {}
        values.each { |value| r[value.to_sym] = hash[value] if hash[value] }
        result[hash['parameterId']] = r
      end
    else
      hash_array.each { |hash| result[hash['parameterId']] = hash[values[0]] }
    end
    result
  end

  def self.split_parameter_array(parameters)
    pages = (parameters.size - 1) / 15 + 1
    request_parameters = []

    pages.times do |i|
      remainder = parameters.size - (i * 15)
      request_parameters[i] = parameters.slice(i * 15, remainder < 15 ? remainder : 15)
    end
    request_parameters
  end

  def self.get_status_items(json)
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
    result.to_json
  end
end
