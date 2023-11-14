#!/usr/bin/env ruby
# frozen_string_literal: true

require 'evdev' if RUBY_PLATFORM.match?(/linux/i)
require 'logger'
require 'rqrcode'
require 'fileutils'
require 'resolv-replace'
require 'httparty'

class BarcodeDuplicator
  def initialize
    @logger = ::Logger.new('log/barcode.log', 1, 1024**2 * 100)
    @logger.info ''
    @logger.info 'Starting barcode scanner...'
    @logger.info "Process PID #{Process.pid}"

    @pidfile = 'tmp/pids/barcode.pid'

    register_signal_handlers
    # FIXME: daemonize if Rails.env.production?
    write_pid
    detect_scanner
  rescue Interrupt
    shutdown
  end

  def fetch_label_from_api(line_item_id)
    headers = { 'Content-Type' => 'application/json; charset=utf-8',
                'Authorization' => "Token token=#{ENV.fetch('SQUARED_API_TOKEN')}" }
    response = HTTParty.get("#{ENV.fetch('API_BASE_URL')}/admin/api/line_items/#{line_item_id}/label",
                            headers:)
    if response.success?
      decoded_label = Base64.decode64(JSON.parse(response.body)['label'])
      File.open('tmp/barcode.pdf', 'w') { |f| f.write(decoded_label) }
      true
    else
      false
    end
  end

  def listen!
    # Generate alphabet
    all_keys = *('0'..'Z').map { |l| :"KEY_#{l}" }
    @device.on(*all_keys) do |state, key|
      @cmd += key.to_s[-1].downcase if state == 1
    end

    # Process command
    @device.on(:KEY_ENTER) do |_state, _key|
      unless @cmd.empty?
        logger.info "Barcode command: #{@cmd}"
        line_item_id = @cmd.to_s[/^SQLI(\d+)\w/i, 1]
        if fetch_label_from_api(line_item_id)
          `lp -d Honeywell_3 -o position=center 'tmp/barcode.pdf'`
        else
          RQRCode::QRCode.new(@cmd).as_png.resize(200, 200).save('tmp/barcode.png')
          `convert 'tmp/barcode.png' -background white -gravity west -extent 600x200 -fill black -pointsize 30 -annotate +200+0 "#{@cmd.upcase}" 'tmp/barcode.png'`
          `lp -d Honeywell_3 -o scaling=100 'tmp/barcode.png'`
        end
        sleep(1)
        `rm 'tmp/barcode.pdf'`
        @cmd = ''
      end
    end

    # Blocks the device for other applications
    @device.grab

    # Main listen loop
    loop do
      @device.handle_event
    rescue Evdev::AwaitEvent
      Kernel.select([@device.event_channel])
      retry
    end
  end

  private

  attr_reader :logger, :pidfile

  def detect_scanner
    # Detect barcode scanner
    # xinput_device = `xinput list | grep "wch.cn"`
    # xinput_device =~ /\w.*id=(\d{1,3}).*/
    # xinput_device_id = Regexp.last_match(1).to_i
    # logger.info "Barcode reader xinput device id #{xinput_device_id}"

    # device_node = `xinput list-props #{xinput_device_id} | grep 'Device Node'`
    # device_node =~ /\w.*\/dev\/input\/event(\d{1,3}).*/
    # device_event_id = Regexp.last_match(1).to_i
    # logger.info "Barcode reader device event id #{device_event_id}"

    # if xinput_device_id == 0 || device_event_id == 0
    #   logger.error 'Exiting barcode reader wasn\'t found!'
    # end

    # Attach device event0 is hardcoded because the pi didn't work with xinput
    @device = Evdev.new('/dev/input/event0')
    @cmd = ''

    # Print device description
    logger.info 'Detected barcode device'
    device_params = %i[name phys uniq vendor_id product_id bustype version driver_version]
    device_params.each do |param|
      logger.info "#{param}: #{@device.send(param)}"
    end
  end

  def register_signal_handlers
    trap('INT') { interrupt }
    trap('TERM') { interrupt }
  end

  def daemonize
    Process.daemon(true, false)
  end

  def write_pid
    File.open(pidfile, 'w') { |f| f << Process.pid }
    at_exit { delete_pidfile }
  end

  def delete_pidfile
    FileUtils.rm_f pidfile
  end

  def interrupt
    raise Interrupt
  end

  def shutdown
    logger.info 'Shutting down barcode daemon'
    @device.ungrab
    exit(0)
  end
end

BarcodeDuplicator.new.listen!
