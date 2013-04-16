module TestDsl

  module Shared
    def fullpath(filename)
      (Pathname.new(__FILE__) + "../../examples/#{filename}.rb").cleanpath.to_s
    end
  end

  include Shared

  def self.included(base)
    base.class_eval do
      before do
        load_defaults
        Byebug.interface = TestInterface.new
        Byebug.handler.display.clear
      end
    end
  end

  ##
  # Loads byebug default settings
  #
  def load_defaults
    Byebug::Command.settings[:byebugtesting] = true
    Byebug::Command.settings[:basename] = false
    Byebug::Command.settings[:callstyle] = :last
    Byebug::Command.settings[:force_stepping] = false
    Byebug::Command.settings[:full_path] = true
    Byebug::Command.settings[:listsize] = 10
    Byebug::Command.settings[:stack_trace_on_error] = false
    Byebug::Command.settings[:tracing_plus] = false
    Byebug::Command.settings[:width] =
      ENV['COLUMNS'].to_i > 10 ? ENV['COLUMNS'].to_i : 80
    Byebug::Command.settings[:argv] = Byebug::ARGV
    Byebug::Command.settings[:autolist] = 1
    Byebug::Command.settings[:autoeval] = 1
    Byebug::Command.settings[:reload_source_on_change] = 1
    force_unset_const Byebug, 'BYEBUG_SCRIPT'
    force_set_const Byebug, 'DEFAULT_START_SETTINGS',
                    init: true, post_mortem: false, tracing: nil
    force_set_const Byebug, 'ARGV', ARGV.clone
    force_set_const Byebug, 'PROG_SCRIPT', $0
    force_set_const Byebug, 'INITIAL_DIR', Dir.pwd
    Byebug.annotate = 0
  end

  ##
  # Adds commands to the input queue, so they will be later retrieved by
  # Processor, i.e., it emulates user's input.
  #
  # If a command is a Proc object, it will be executed before being retrieved by
  # Processor. May be handy when you need build a command depending on the
  # current context/state.
  #
  # Usage:
  #   enter 'b 12'
  #   enter 'b 12', 'cont'
  #   enter ['b 12', 'cont']
  #   enter 'b 12', ->{"disable #{breakpoint.id}"}, 'cont'
  #
  def enter(*messages)
    messages = messages.first.is_a?(Array) ? messages.first : messages
    interface.input_queue.concat(messages)
  end

  ##
  # Runs byebug with the provided basename for a file.
  #
  # The file should be placed in the test/examples dir. You also can specify a
  # block, which will be executed when Processor extracts all the commands from
  # the input queue. You can use that for making asserts on the current test. If
  # you specified the block and it never was executed, the test will fail.
  #
  # The Byebug::PROG_SCRIPT constant will be set to the file to be debugged
  # unless the second parameter says otherwise.
  #
  # Usage:
  #   debug "ex1" # ex1 should be placed in test/examples/ex1.rb
  #
  #   enter 'b 4', 'cont'
  #   debug("ex1") { state.line.must_equal 4 }
  #
  def debug_file(filename, set_prog_script = false, &block)
    is_test_block_called = false
    debug_completed = false
    exception = nil
    Byebug.stubs(:run_init_script)
    if block
      interface.test_block= lambda do
        is_test_block_called = true
        # We need to store exception and reraise it after completing debugging,
        # because Byebug will swallow any exceptions, so e.g. our failed
        # assertions will be ignored
        begin
          block.call
        rescue Exception => e
          exception = e
          raise e
        end
      end
    end
    if set_prog_script
      force_set_const(Byebug, 'PROG_SCRIPT', Pathname.new(fullpath(filename)))
    end
    Byebug.start do
      load fullpath(filename)
      debug_completed = true
    end
    flunk "Debug block was not completed" unless debug_completed
    flunk "Test block was provided, but not called" if block && !is_test_block_called
    raise exception if exception
  end

  ##
  # Checks the output of byebug.
  #
  # By default it checks output queue of the current interface, but you can
  # check again any queue by providing it as a second argument.
  #
  # Usage:
  #   enter 'break 4', 'cont'
  #   debug 'ex1'
  #   check_output "Breakpoint 1 at #{fullpath('ex1')}:4"
  #
  def check_output(check_method, *args)
    queue = args.last.is_a?(String) || args.last.is_a?(Regexp) ?
            interface.output_queue : args.pop
    queue_messages = queue.map(&:strip)
    messages = Array(args).map { |msg| msg.is_a?(String) ? msg.strip : msg }
    queue_messages.send(check_method, messages)
  end

  def check_error_includes(*args)
    check_output :must_include_in_order, *args, interface.error_queue
  end

  def check_output_includes(*args)
    check_output :must_include_in_order, *args
  end

  def check_output_doesnt_include(*args)
    check_output :wont_include_in_order, *args
  end

  def interface
    Byebug.handler.interface
  end

  def state
    $byebug_state
  end

  def context
    state.context
  end

  def force_set_const(klass, const, value)
    force_unset_const(klass, const)
    klass.const_set(const, value)
  end

  def force_unset_const(klass, const)
    klass.send(:remove_const, const) if klass.const_defined?(const)
  end

  def change_line_in_file(file, line, new_line_content)
    old_content = File.read(file)
    new_content = old_content.split("\n").tap { |c| c[line - 1] = new_line_content }.join("\n")
    File.open(file, 'w') { |f| f.write(new_content) }
  end

  def temporary_change_method_value(item, method, value)
    old = item.send(method)
    item.send("#{method}=", value)
    yield
  ensure
    item.send("#{method}=", old)
  end

  def temporary_change_hash_value(item, key, value)
    old_value = item[key]
    item[key] = value
    yield
  ensure
    item[key] = old_value
  end

  def temporary_set_const(klass, const, value)
    old_value = klass.const_defined?(const) ? klass.const_get(const) : :__undefined__
    force_set_const(klass, const, value)
    yield
  ensure
    if old_value == :__undefined__
      klass.send(:remove_const, const)
    else
     force_set_const(klass, const, old_value)
    end
  end

end
