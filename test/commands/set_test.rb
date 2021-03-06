module Byebug
  #
  # Test settings functionality.
  #
  class SetTestCase < TestCase
    def program
      strip_line_numbers <<-EOC
        1:  module Byebug
        2:    byebug
        3:
        4:    z = 4
        5:    z + 1
        6:  end
      EOC
    end

    settings = %i(autoeval autolist autosave basename fullpath post_mortem
                  stack_on_error)

    settings.each do |set|
      ['on', '1', 'true', ''].each do |key|
        define_method(:"test_enable_boolean_setting_#{set}_using_#{key}") do
          with_setting set, false do
            enter "set #{set} #{key}"
            debug_code(program)

            assert_equal true, Setting[set]
          end
        end
      end

      %w(off 0 false).each do |key|
        define_method(:"test_disable_boolean_setting_#{set}_using_#{key}") do
          with_setting set, true do
            enter "set #{set} #{key}"
            debug_code(program)

            assert_equal false, Setting[set]
          end
        end
      end

      define_method(:"test_disable_boolean_setting_#{set}_using_no_prefix") do
        with_setting set, true do
          enter "set no#{set}"
          debug_code(program)

          assert_equal false, Setting[set]
        end
      end
    end

    def test_set_does_not_enable_a_setting_using_shorcut_when_ambiguous
      with_setting :autoeval, false do
        enter 'set auto'
        debug_code(program)

        assert_equal false, Setting[:autoeval]
      end
    end

    def test_set_enables_a_setting_using_shorcut_when_not_ambiguous
      with_setting :autoeval, false do
        enter 'set autoe'
        debug_code(program)

        assert_equal true, Setting[:autoeval]
      end
    end

    def test_set_does_not_disable_a_setting_using_shorcut_when_ambiguous
      with_setting :autoeval, true do
        enter 'set noauto'
        debug_code(program)

        assert_equal true, Setting[:autoeval]
      end
    end

    def test_set_histsize_sets_maximum_history_size
      with_setting :histsize, 1 do
        enter 'set histsize 250'
        debug_code(program)

        assert_equal 250, Setting[:histsize]
        check_output_includes "Maximum size of byebug's command history is 250"
      end
    end

    def test_set_histsize_shows_an_error_message_if_no_size_is_provided
      enter 'set histsize'
      debug_code(program)
      check_error_includes 'You must specify a value for setting :histsize'
    end

    def test_set_histfile_sets_command_history_file
      filename = File.expand_path('.custom-byebug-hist')
      enter "set histfile #{filename}"
      debug_code(program)
      assert_equal filename, Setting[:histfile]
      check_output_includes "The command history file is #{filename}"
      Setting[:histfile] = HistfileSetting::DEFAULT
      File.delete(filename)
    end

    def test_set_histfile_shows_an_error_message_if_no_filename_is_provided
      enter 'set histfile'
      debug_code(program)
      check_error_includes 'You must specify a value for setting :histfile'
    end

    [:listsize, :width].each do |set|
      define_method(:"test_set_#{set}_changes_integer_setting_#{set}") do
        with_setting set, 100 do
          enter "set #{set} 50"
          debug_code(program)

          assert_equal 50, Setting[set]
        end
      end
    end

    def test_verbose_prints_tracepoint_api_event_information
      enter 'set verbose'
      debug_code(program)
      assert_equal true, Byebug.verbose?
      Byebug.verbose = false
    end

    def test_set_without_arguments_shows_help_for_set_command
      enter 'set'
      debug_code(program)
      check_output_includes(/Modifies parts of byebug environment./)
      check_output_includes(/List of settings supported in byebug/)
    end
  end
end
