# frozen_string_literal: true
# Copyright (c) 1999-2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.
# For details of the GNU LGPL, see the file "COPYING".

require 'racc/source'
require 'racc/parser-text'
require 'rbconfig'

module Racc
  # generate parser file
  #
  # rubocop:disable Metrics/ClassLength
  class ParserFileGenerator
    # This class manager meta data of ParserFileGenerator.
    class Params
      def self.bool_attr(name)
        module_eval(<<-End)
          def #{name}?
            @#{name}
          end

          def #{name}=(b)
            @#{name} = b
          end
        End
      end

      attr_accessor :file
      attr_accessor :classname
      attr_accessor :superclass
      bool_attr :result_var
      attr_accessor :header
      attr_accessor :inner
      attr_accessor :footer

      bool_attr :debug_parser
      bool_attr :embed_runtime
      bool_attr :make_executable
      attr_accessor :interpreter

      def initialize
        # Parameters derived from parser
        self.file = nil
        self.classname = nil
        self.superclass = 'Racc::Parser'
        self.result_var = true
        self.header = []
        self.inner  = []
        self.footer = []

        # Parameters derived from command line options
        self.debug_parser = false
        self.embed_runtime = false
        self.make_executable = false
        self.interpreter = nil
      end
    end

    def initialize(states, params)
      @states = states
      @grammar = states.grammar
      @params = params

      @indent_re_cache = {}
    end

    def generate_parser
      string_io = StringIO.new

      init_line_conversion_system
      @f = string_io
      parser_file

      string_io.rewind
      string_io.read
    end

    def generate_parser_file(destpath)
      init_line_conversion_system
      if destpath == '-'
        @f = $stdout
        parser_file
      else
        File.open(destpath, 'w') do |f|
          @f = f
          parser_file
        end
        File.chmod(0755, destpath) if @params.make_executable?
      end
    end

    private

    def parser_file
      Color.without_color do
        shebang(@params.interpreter) if @params.make_executable?
        notice
        line
        if @params.embed_runtime?
          embed_library(runtime_source)
        else
          require 'racc/parser.rb'
        end
        header
        parser_class(@params.classname, @params.superclass) do
          inner
          state_transition_table
        end
        footer
      end
    end

    c = ::RbConfig::CONFIG
    RUBY_PATH = "#{c['bindir']}/#{c['ruby_install_name']}#{c['EXEEXT']}".freeze

    def shebang(path)
      line '#!' + (path == 'ruby' ? RUBY_PATH : path)
    end

    def notice
      line '#'
      line '# DO NOT MODIFY!!!!'
      line %(# This file was automatically generated by Racc #{Racc::VERSION})
      codename = Racc::CODENAME
      filename = @params.file.name
      line %[# (codename: #{codename}) from Racc grammar file "#{filename}".]
      line '#'
    end

    def runtime_source
      Source::Buffer.new('racc/parser.rb', ::Racc::PARSER_TEXT)
    end

    def embed_library(src)
      line %(###### #{src.name} begin)
      line %(unless $".index '#{src.name}')
      line %($".push '#{src.name}')
      put src
      line %(end)
      line %(###### #{src.name} end)
    end

    def require(feature)
      line "require '#{feature}'"
    end

    def parser_class(classname, superclass)
      mods = classname.split('::')
      classid = mods.pop
      mods.each do |mod|
        indent; line "module #{mod}"
        cref_push mod
      end
      indent; line "class #{classid} < #{superclass}"
      cref_push classid
      yield
      cref_pop
      indent; line "end   \# class #{classid}"
      mods.reverse_each do |mod|
        indent; line "end   \# module #{mod}"
        cref_pop
      end
    end

    def header
      @params.header.each do |src|
        line
        put src
      end
    end

    def inner
      @params.inner.each do |src|
        line
        put src
      end
    end

    def footer
      @params.footer.each do |src|
        line
        put src
      end
    end

    # Low Level Routines

    def put(src)
      replace_location(src) do
        @f.puts src.text
      end
    end

    def line(str = '')
      @f.puts str
    end

    def init_line_conversion_system
      @cref = []
      @used_separator = {}
    end

    def cref_push(name)
      @cref.push name
    end

    def cref_pop
      @cref.pop
    end

    def indent
      @f.print '  ' * @cref.size
    end

    def toplevel?
      @cref.empty?
    end

    def replace_location(src)
      sep = make_separator(src)
      @f.print 'Object.' if toplevel?
      @f.puts "module_eval(<<'#{sep}', '#{src.name}', #{src.lineno})"
      yield
      @f.puts sep
    end

    def make_separator(src)
      sep = unique_separator(src.name)
      sep *= 2 while src.text.index(sep)
      sep
    end

    def unique_separator(id)
      sep = "...end #{id}/module_eval..."

      if @used_separator.key?(sep)
        suffix = 2
        suffix += 1 while @used_separator.key?("#{sep}#{suffix}")
        sep = "#{sep}#{suffix}"
      end

      @used_separator[sep] = true
      sep
    end

    # State Transition Table Serialization

    public

    def put_state_transition_table(f)
      @f = f
      state_transition_table
    end

    private

    # rubocop:disable Metrics/AbcSize
    # rubocop:disable Metrics/MethodLength
    def state_transition_table
      table = @states.state_transition_table
      table.use_result_var = @params.result_var?
      table.debug_parser = @params.debug_parser?

      line '##### State transition tables begin ###'
      %w(
        action_table action_check action_pointer action_default
        goto_table goto_check goto_pointer goto_default
      ).each do |table_type|
        line
        integer_list "racc_#{table_type}", table.send(table_type)
      end
      line
      i_i_sym_list 'racc_reduce_table', table.reduce_table
      line
      line "racc_reduce_n = #{table.reduce_n}"
      line
      line "racc_shift_n = #{table.shift_n}"
      line
      sym_int_hash 'racc_token_table', table.token_table
      line
      line "racc_nt_base = #{table.nt_base}"
      line
      line "racc_use_result_var = #{table.use_result_var}"
      line
      @f.print(unindent_auto(<<-End))
        Racc_arg = [
          racc_action_table,
          racc_action_check,
          racc_action_default,
          racc_action_pointer,
          racc_goto_table,
          racc_goto_check,
          racc_goto_default,
          racc_goto_pointer,
          racc_nt_base,
          racc_reduce_table,
          racc_token_table,
          racc_shift_n,
          racc_reduce_n,
          racc_use_result_var ]
      End
      line
      string_list 'Racc_token_to_s_table', table.token_to_s_table
      line
      line "Racc_debug_parser = #{table.debug_parser}"
      line
      line '##### State transition tables end #####'
      actions
    end
    # rubocop:enable Metrics/AbcSize
    # rubocop:enable Metrics/MethodLength

    def integer_list(name, table)
      lines = table.inspect.split(/((?:\w+, ){15})/).reject(&:empty?)
      line "#{name} = #{lines.join("\n")}"
    end

    def i_i_sym_list(name, table)
      sep = ''
      line "#{name} = ["
      table.each_slice(3) do |len, target, mid|
        @f.print sep; sep = ",\n"
        @f.printf '  %d, %d, %s', len, target, mid.inspect
      end
      line ' ]'
    end

    def sym_int_hash(name, h)
      sep = "\n"
      @f.print "#{name} = {"
      h.to_a.sort_by { |_sym, i| i }.each do |sym, i|
        @f.print sep; sep = ",\n"
        @f.printf '  %s => %d', sym.serialized, i
      end
      line ' }'
    end

    def string_list(name, list)
      sep = '  '
      line "#{name} = ["
      list.each do |s|
        @f.print sep; sep = ",\n  "
        @f.print s.dump
      end
      line ' ]'
    end

    def actions
      if @grammar.any? { |rule| !rule.action.source? }
        fail 'racc: fatal: cannot generate parser file ' \
             'when any action is a Proc'
      end

      if @params.result_var?
        decl = ', result'
        retval = "\n    result"
      else
        decl = ''
        retval = ''
      end
      generate_reduce_actions(decl, retval)
      line
      @f.printf unindent_auto(<<-'End'), decl
        def _reduce_none(val, _values%s)
          val[0]
        end
      End
      line
    end

    def generate_reduce_actions(decl, retval)
      @grammar.each do |rule|
        line
        if rule.action.empty?
          line "# reduce #{rule.ident} omitted"
        else
          generate_reduce_action(rule, decl, retval)
        end
      end
    end

    def generate_reduce_action(rule, decl, retval)
      src0  = rule.action.source
      src   = src0.drop_leading_blank_lines
      delim = make_delimiter(src.text)
      @f.printf unindent_auto(<<-End),
          module_eval(<<'%s', '%s', %d)
            def _reduce_%d(val, _values%s)
              %s%s
            end
          %s
        End
                delim, src.name, src.lineno - 1,
                rule.ident, decl,
                src.text, retval,
                delim
    end

    def make_delimiter(body)
      delim = '.,.,'
      delim *= 2 while body.index(delim)
      delim
    end

    def unindent_auto(str)
      lines = str.lines.to_a
      n = minimum_indent(lines)
      lines.map do |line|
        detab(line).sub(indent_re(n), '').rstrip + "\n"
      end.join('')
    end

    def minimum_indent(lines)
      lines.map { |line| n_indent(line) }.min
    end

    def n_indent(line)
      line.slice(/\A\s+/).size
    end

    def indent_re(n)
      @indent_re_cache[n] ||= /\A {#{n}}/
    end

    def detab(str, ts = 8)
      add = 0
      len = nil
      str.gsub(/\t/) do
        len = ts - ($`.size + add) % ts
        add += len - 1
        ' ' * len
      end
    end
  end
  # rubocop:enable Metrics/ClassLength
end
