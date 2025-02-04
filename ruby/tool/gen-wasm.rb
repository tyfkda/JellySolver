#!/usr/bin/env ruby
# frozen_string_literal: true

case ARGV[0]
when 'build'
  FileUtils.mkdir_p('./build')
  command = %w[build --ruby-version 3.3 -o ./build/ruby-js.wasm]
when 'pack'
  FileUtils.mkdir_p('./docs')
  command = %w[pack ./build/ruby-js.wasm --dir ./jelly::/lib --dir ../stagedata::/stagedata -o ./docs/jelly-solver.wasm]
else
  puts "Invalid argument. Use 'build' or 'pack'."
  exit 1
end

ENV['BUNDLE_ONLY'] = 'wasm'

require 'bundler/setup'
require 'ruby_wasm'
require 'ruby_wasm/cli'

# Exclude all gems except the 'js' gem for packaging
definition = Bundler.definition
excluded_gems = definition.resolve.materialize(definition.requested_dependencies).map(&:name)
excluded_gems -= %w[js]
RubyWasm::Packager::EXCLUDED_GEMS.concat(excluded_gems)

RubyWasm::CLI.new(stdout: $stdout, stderr: $stderr).run(command)
