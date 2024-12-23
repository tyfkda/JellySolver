#! /usr/bin/env ruby

require_relative 'jelly/jelly'
require_relative 'jelly/solver'
require_relative 'jelly/stage'
require_relative 'jelly/stage_parser'

def disp_stage(stage)
    lines = stage.make_lines()
    lines.each do |line|
        puts line
    end
end

def main(fn)
    stage = File.open(fn) do |f|
        stage_parser = Jelly::StageParser.new()
        stage_parser.parse(f)
    end

    disp_stage(stage)

    solver = Jelly::Solver.new()
    solver.solve(stage) do |next_stage, move|
        p move
        disp_stage(next_stage)
    end
end

if __FILE__ == $0
    if ARGV.length != 1
        $stderr.puts "Usage: #{$0} <stage_file>"
        exit(1)
    end
    main(ARGV[0])
end
