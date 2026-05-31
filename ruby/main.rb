#! /usr/bin/env ruby

require_relative 'jelly/jelly'
require_relative 'jelly/solver'
require_relative 'jelly/stage'
require_relative 'jelly/stage_parser'
require_relative 'disp_interactive'

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

    solver = Jelly::Solver.new(**options[:solver])
    moves = nil
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    if options[:profiling]
        StackProf.run(out: '/tmp/stackprof.dump') do
            moves = solver.solve(stage.dup())
        end
    else
        moves = solver.solve(stage.dup())
    end
    end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    unless moves.nil?
        unless options[:solver][:quiet]
            if options[:interactive]
                disp_solution_interactive(stage, moves)
                return true
            end

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
        solver: {
            no_prune: false,
            use_bfs: false,
            quiet: false,
            parallel: false,
        },
        interactive: false,
        profiling: false,
    }
    opt = OptionParser.new
    opt.on('--no-prune') {|_| options[:solver][:no_prune] = true}
    opt.on('--bfs') {|_| options[:solver][:use_bfs] = true}
    opt.on('--quiet') {|_| options[:solver][:quiet] = true}
    opt.on('--parallel') {|_| options[:solver][:parallel] = true}
    opt.on('--interactive') {|_| options[:interactive] = true}
    opt.on('--prof') do |_|
        options[:profiling] = true
        require 'stackprof'  # プロファイラを使う場合にのみrequire
    end
    opt.parse!(ARGV)

    if ARGV.length != 1
        $stderr.puts "Usage: #{$0} <stage_file>"
        exit(1)
    end
    main(ARGV[0], options)
end
