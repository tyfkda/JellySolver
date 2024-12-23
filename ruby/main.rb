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

def disp_solution(stage, moves)
    disp_stage(stage)
    moves.each do |move|
        p move
        jelly = stage.jellies.find {|it| it.occupy_position?(move[0], move[1])}
        stage = Jelly::Solver.move_jelly(stage, jelly, move[2])
        raise "Invalid move: #{move}" if stage.nil?
        disp_stage(stage)
    end
end

def main(fn, options = {})
    stage = File.open(fn) do |f|
        stage_parser = Jelly::StageParser.new()
        stage_parser.parse(f)
    end

    solver = Jelly::Solver.new(**options)
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    moves = solver.solve(stage)
    end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    unless moves.nil?
        unless options[:quiet]
            $stderr.puts "\rSolved!\x1b[0K"
            disp_solution(stage, moves)
        end
        puts "Steps=#{moves.length}, check=#{solver.check_count}, elapsed=#{sprintf("%.3f", end_time - start_time)}s"
        return true
    else
        puts "\rNo solution found. check=#{solver.check_count}, elapsed=#{sprintf("%.3f", end_time - start_time)}s"
        return false
    end
end

if __FILE__ == $0
    require 'optparse'

    options = {
        quiet: false,
    }
    opt = OptionParser.new
    opt.on('--quiet') {|_| options[:quiet] = true}
    opt.parse!(ARGV)

    if ARGV.length != 1
        $stderr.puts "Usage: #{$0} <stage_file>"
        exit(1)
    end
    main(ARGV[0], options)
end
