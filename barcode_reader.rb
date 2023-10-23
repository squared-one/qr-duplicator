#!/usr/bin/env ruby
# frozen_string_literal: true

require 'evdev' if RUBY_PLATFORM.match?(/linux/i)
require 'logger'

class BarcodeScanner

  def initialize
    @logger = ::Logger.new('log/barcode.log', 1, 1024 ** 2 * 100)
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

  def listen!
    # Generate alphabet
    all_keys = *('0'..'Z').map { |l| :"KEY_#{l}" }
    @device.on(*all_keys) do |state, key|
      if state == 1
        @cmd += key.to_s[-1].downcase
      end
    end

    # Process command
    @device.on(:KEY_ENTER) do |state, key|
      unless @cmd.empty?

        logger.info "Barcode command: #{@cmd}"

        @cmd = ''
      end
    end

    # Blocks the device for other applications
    @device.grab

    # Main listen loop
    loop do
      begin
        @device.handle_event
      rescue Evdev::AwaitEvent
        Kernel.select([@device.event_channel])
        retry
      end
    end
  end

  private
    attr_reader :logger, :pidfile

    def detect_scanner
      # Detect barcode scanner
      xinput_device = `xinput list | grep "wch.cn"`
      xinput_device =~ /\w.*id=(\d{1,3}).*/
      xinput_device_id = Regexp.last_match(1).to_i
      logger.info "Barcode reader xinput device id #{xinput_device_id}"

      device_node = `xinput list-props #{xinput_device_id} | grep 'Device Node'`
      device_node =~ /\w.*\/dev\/input\/event(\d{1,3}).*/
      device_event_id = Regexp.last_match(1).to_i
      logger.info "Barcode reader device event id #{device_event_id}"

      if xinput_device_id == 0 || device_event_id == 0
        logger.error 'Exiting barcode reader wasn\'t found!'
        raise BarcodeNotFound
      end

      # Attach device
      @device = Evdev.new("/dev/input/event#{device_event_id}")
      @cmd = ''

      # Print device description
      logger.info 'Detected barcode device'
      device_params = [:name, :phys, :uniq, :vendor_id, :product_id, :bustype, :version, :driver_version]
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