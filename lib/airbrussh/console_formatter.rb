require "airbrussh/colors"
require "airbrussh/command_formatter"
require "airbrussh/console"
require "airbrussh/rake/command"
require "airbrussh/rake/context"
require "sshkit"

module Airbrussh
  class ConsoleFormatter < SSHKit::Formatter::Abstract
    include Airbrussh::Colors
    extend Forwardable

    attr_reader :config, :context
    def_delegator :context, :current_task_name

    def initialize(io, config=Airbrussh.configuration)
      super(io)

      @config = config
      @context = Airbrussh::Rake::Context.new(config)
      @console = Airbrussh::Console.new(original_output, config)

      write_banner
    end

    def write_banner
      print_line(config.banner_message) if config.banner_message
    end

    def log_command_start(command)
      command = decorate(command)
      write_command_start(command)
    end

    def log_command_data(command, stream_type, line)
      command = decorate(command)
      write_command_output_line(command, stream_type, line)
    end

    def log_command_exit(command)
      command = decorate(command)
      write_command_exit(command)
    end

    def write(obj)
      case obj
      when SSHKit::Command
        command = decorate(obj)
        write_command_start(command)
        write_command_output(command, :stderr)
        write_command_output(command, :stdout)
        write_command_exit(command) if command.finished?
      when SSHKit::LogMessage
        write_log_message(obj)
      end
    end
    alias_method :<<, :write

    private

    attr_accessor :last_printed_task

    def write_log_message(log_message)
      return if debug?(log_message)
      print_task_if_changed
      print_indented_line(gray(log_message.to_s))
    end

    def write_command_start(command)
      return if debug?(command)
      print_task_if_changed
      print_indented_line(command.start_message) if command.first_execution?
    end

    # For SSHKit versions up to and including 1.7.1, the stdout and stderr
    # output was available as attributes on the Command. Print the data for
    # the specified command and stream if enabled
    # (see Airbrussh::Configuration#command_output).
    def write_command_output(command, stream)
      output = command.public_send(stream)
      return if output.empty?
      output.lines.to_a.each do |line|
        write_command_output_line(command, stream, line)
      end
      command.public_send("#{stream}=", "")
    end

    def write_command_output_line(command, stream, line)
      hide_command_output = !config.show_command_output?(stream)
      return if hide_command_output || debug?(command)
      print_indented_line(command.format_output(line))
    end

    def print_task_if_changed
      return if current_task_name.nil?
      return if current_task_name == last_printed_task

      self.last_printed_task = current_task_name
      print_line("#{clock} #{blue(current_task_name)}")
    end

    def write_command_exit(command)
      return if debug?(command)
      print_indented_line(command.exit_message(@log_file), -2)
    end

    def clock
      @start_at ||= Time.now
      duration = Time.now - @start_at

      minutes = (duration / 60).to_i
      seconds = (duration - minutes * 60).to_i

      format("%02d:%02d", minutes, seconds)
    end

    def debug?(obj)
      obj.verbosity <= SSHKit::Logger::DEBUG
    end

    def decorate(command)
      Airbrussh::CommandFormatter.new(@context.decorate_command(command))
    end

    def print_line(string)
      @console.print_line(string)
    end

    def print_indented_line(string, offset=0)
      indent = " " * (6 + offset)
      print_line([indent, string].join)
    end
  end
end