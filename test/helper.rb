$VERBOSE = true

require 'minitest/autorun'

require 'racc'
require 'racc/parser'
require 'racc/grammar_file_parser'
require 'racc/parser_file_generator'

require 'fileutils'
require 'tempfile'
require 'timeout'

module Racc
  class TestCase < Minitest::Test
    PROJECT_DIR = File.expand_path(File.join(File.dirname(__FILE__), '..'))
    RACC        = File.join(PROJECT_DIR, 'bin', 'racc')

    TAB_DIR     = File.join('test', 'tab')     # generated parsers go here
    ASSET_DIR   = File.join('test', 'assets')  # test grammars
    REGRESS_DIR = File.join('test', 'regress') # known-good generated outputs

    INC = [
      File.join(PROJECT_DIR, 'lib'),
      File.join(PROJECT_DIR, 'ext')
    ].join(':')

    def setup
      FileUtils.mkdir_p(File.join(PROJECT_DIR, TAB_DIR))
    end

    def teardown
      FileUtils.rm_rf(File.join(PROJECT_DIR, TAB_DIR))
    end

    def assert_compile(asset, args = '', expect_success = true)
      file = File.basename(asset, '.y')
      args = [
        args,
        "#{ASSET_DIR}/#{file}.y",
        "-o#{TAB_DIR}/#{file}"
      ]
      racc args.join(' '), expect_success
    end

    def assert_error(asset, args = '')
      assert_compile asset, args, false
    end

    # rubocop:disable Metric/AbcSize
    # rubocop:disable Metrics/CyclomaticComplexity
    def assert_warnings(dbg_output, expected)
      assert_equal expected[:useless_nts]   || 0, useless_nts(dbg_output)
      assert_equal expected[:useless_terms] || 0, useless_terms(dbg_output)
      assert_equal expected[:sr_conflicts]  || 0, sr_conflicts(dbg_output)
      assert_equal expected[:rr_conflicts]  || 0, rr_conflicts(dbg_output)
      assert_equal expected[:useless_prec]  || 0, useless_prec(dbg_output)
      assert_equal expected[:useless_rules] || 0, useless_rules(dbg_output)
    end
    # rubocop:enable Metric/AbcSize
    # rubocop:enable Metrics/CyclomaticComplexity

    def assert_no_warnings(dbg_output)
      assert_warnings(dbg_output, {})
    end

    def assert_exec(asset)
      file = File.basename(asset, '.y')
      Dir.chdir(PROJECT_DIR) do
        ruby("#{TAB_DIR}/#{file}")
      end
    end

    def assert_parser_unchanged(asset)
      file = File.basename(asset, '.y')

      result = Dir.chdir(PROJECT_DIR) do
        File.read("#{REGRESS_DIR}/#{file}.rb") ==
          File.read("#{TAB_DIR}/#{file}")
      end

      assert(result, "Output of test/assets/#{asset} differed from " \
        "expectation. Try compiling it and diff with test/regress/#{file}.rb:" \
        "\nruby -I./lib ./bin/racc -o tmp/#{file} test/assets/#{asset}; " \
        "colordiff tmp/#{file} test/regress/#{file}.rb")
    end

    def assert_output_unchanged(file, args, actual = nil)
      unless actual
        actual = args
        args = nil
      end
      result = Dir.chdir(PROJECT_DIR) do
        File.read("#{REGRESS_DIR}/#{file}") == actual
      end

      assert(result, build_assert_out_unchanged_message(file, args))
    end

    def build_assert_out_unchanged_message(file, args)
      asset = File.basename(file, '.out') + '.y'
      "Console output of test/assets/#{asset} differed from " \
        'expectation. Try compiling it and diff stderr with ' \
        "test/regress/#{file}:\nruby -I./lib ./bin/racc #{args} -o /dev/null " \
        "test/assets/#{asset} 2>tmp/#{file}; colordiff tmp/#{file} " \
        "test/regress/#{file}"
    end

    def assert_html_unchanged(asset)
      assert_compile asset, '-S'

      file = File.basename(asset, '.y')
      result = Dir.chdir(PROJECT_DIR) do
        File.read("#{REGRESS_DIR}/#{file}.html") ==
          File.read("#{TAB_DIR}/#{file}")
      end

      assert(result, build_assert_html_unchanged_message(asset, file))
    end

    def build_assert_html_unchanged_message(asset, file)
      "HTML state summary for test/assets/#{asset} differed from " \
      'expectation. Try compiling it and diff with ' \
      "test/regress/#{file}.html:" \
      "\nruby -I./lib ./bin/racc -S -o tmp/#{file} " \
      "test/assets/#{asset}; " \
      "colordiff tmp/#{file} test/regress/#{file}.html"
    end

    def assert_not_conflict(states)
      grammar = states.grammar

      assert_equal 0, states.sr_conflicts.size
      assert_equal 0, states.rr_conflicts.size
      assert_equal 0, grammar.useless_symbols.size
      assert_nil grammar.n_expected_srconflicts
    end

    def racc(arg, expect_success = true)
      ruby "#{RACC} #{arg}", expect_success
    end

    def ruby(arg, expect_success = true)
      Dir.chdir(PROJECT_DIR) do
        Tempfile.open('test') do |io|
          result = system("#{build_ruby_cmd} -I #{INC} #{arg} 2>#{io.path}")
          io.flush
          err = io.read
          assert(result, err) if expect_success
          return err
        end
      end
    end

    def build_ruby_cmd
      executable = ENV['_'] || Gem.ruby
      if File.basename(executable) == 'bundle'
        executable = executable.dup << ' exec ruby'
      end
      executable
    end

    def useless_nts(dbg_output)
      dbg_output.scan(/Useless nonterminal/).size
    end

    def useless_terms(dbg_output)
      dbg_output.scan(/Useless terminal/).size
    end

    def sr_conflicts(dbg_output)
      dbg_output.scan(%r{Shift/reduce conflict}).size
    end

    def rr_conflicts(dbg_output)
      dbg_output.scan(%r{Reduce/reduce conflict}).size
    end

    def useless_prec(dbg_output)
      dbg_output.scan(/The explicit precedence declaration on this rule/).size
    end

    def useless_rules(dbg_output)
      dbg_output.scan(/This rule will never be used due to low precedence/).size
    end
  end
end
