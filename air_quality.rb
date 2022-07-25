require "bundler/setup"
require "uart"
require "io/wait"

# https://cdn-shop.adafruit.com/product-files/3686/plantower-pms5003-manual_v2-3.pdf
class PMS5003
  attr_reader :interface, :baud_rate

  def initialize(interface: "/dev/ttyS0", baud_rate: 9600, mode: "8N1")
    @interface = interface
    @baud_rate = baud_rate
    @mode = mode
  end

  def start
    uart = UART.open interface, baud_rate, '8N1'

    loop do
      uart.wait_readable
      start1, start2 = uart.read(2).bytes

      # According to the data sheet, packets always start with 0x42 and 0x4d
      unless start1 == 0x42 && start2 == 0x4d
        # skip a sample
        uart.read
        next
      end

      length = uart.read(2).unpack('n').first
      data = uart.read(length)
      crc  = 0x42 + 0x4d + 28 + data.bytes.first(26).inject(:+)
      data = data.unpack('n14')

      next unless crc == data.last # crc failure

      sample = Sample.new(Time.now.utc, *data.first(12))
      log sample
    end
  end

  def log(sample)
    puts sample.time
    puts "PM2.5 #{sample.pm2_5_standard}μg/m3: #{sample.pm2_5}"
    puts "PM10 #{sample.pm10_standard}μg/m3: #{sample.pm10}"
    puts
  end
end

class Sample < Struct.new(:time,
                          :pm1_0_standard, :pm2_5_standard, :pm10_standard,
                          :pm1_0_env,      :pm2_5_env,
                          :concentration_unit,
                          :particle_03um,   :particle_05um,   :particle_10um,
                          :particle_25um,   :particle_50um,   :particle_100um)

  def pm2_5
    case pm2_5_standard
    when 0..12
      "Good"
    when 12..35
      "Moderate"
    when 35..55
      "Unhealthy for sensitive individuals"
    when 55..150
      "Unhealthy"
    when 150..250
      "Very Unhealthy"
    else
      "Hazardous"
    end
  end

  def pm10
    case pm10_standard
    when 0..55
      "Good"
    when 55..154
      "Moderate"
    when 155..254
      "Unhealthy for sensitive individuals"
    when 255..354
      "Unhealthy"
    when 355..424
      "Very Unhealthy"
    else
      "Hazardous"
    end
  end
end

pms = PMS5003.new
pms.start
