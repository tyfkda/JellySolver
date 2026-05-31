#!/usr/bin/env ruby

require 'open3'
require 'optparse'
require 'timeout'
require 'tempfile'

def run(fn, options: {})
    print "#{Time.now.strftime('%H:%M:%S')} #{File.basename(fn)}: "

    command = [
        'bundle', 'exec', 'ruby', 'main.rb', '--quiet',
        options[:no_prune] ? '--no-prune' : nil,
        options[:use_bfs] ? '--bfs' : nil,
        fn,
    ].compact

    tmp_out = Tempfile.new('jelly_solver_out')
    tmp_err = Tempfile.new('jelly_solver_err')

    pid = nil
    status = nil
    start_time = Time.now

    begin
        pid = Process.spawn(*command, out: tmp_out.path, err: tmp_err.path)
        if options[:timeout]
            Timeout.timeout(options[:timeout]) do
                _, status = Process.wait2(pid)
            end
        else
            _, status = Process.wait2(pid)
        end
    rescue Timeout::Error
        if pid
            begin
                Process.kill("KILL", pid)
                Process.wait2(pid)
            rescue Errno::ESRCH, Errno::ECHILD
            end
        end
        elapsed = Time.now - start_time
        puts "Timeout (killed after #{sprintf("%.3f", elapsed)}s)"
        return
    ensure
        tmp_out.rewind
        out = tmp_out.read
        tmp_out.close
        tmp_out.unlink

        tmp_err.rewind
        err = tmp_err.read
        tmp_err.close
        tmp_err.unlink
    end

    if status.nil? || status.exitstatus != 0
        puts "Failed (exit status #{status ? status.exitstatus : 'unknown'})"
        if err && !err.empty?
            puts err
        end
    else
        if /Steps=(\d+), check=(\d+), elapsed=(\d+\.\d+)s/ =~ out
            steps = $1.to_i
            check = $2.to_i
            elapsed = $3.to_f
            puts "Steps=#{steps}, check=#{check}, elapsed=#{sprintf("%.3f", elapsed)}s"
        elsif /No solution found\. check=(\d+), elapsed=(\d+\.\d+)s/ =~ out
            check = $1.to_i
            elapsed = $2.to_f
            puts "No solution (check=#{check}, elapsed=#{sprintf("%.3f", elapsed)}s)"
        else
            puts "Result extraction failed: #{out.inspect}"
        end
    end
end

def main(fns, dir, pattern, exclude, greater, options)
    if fns.empty?
        fns = Dir.glob("#{dir}/*").sort
        unless pattern.nil?
            fns.filter! {|fn| pattern =~ File.basename(fn)}
        end
        unless exclude.nil?
            fns.filter! {|fn| !(exclude =~ File.basename(fn))}
        end
        unless greater.nil?
            fns.filter! {|fn| (/(\d+)/ =~ File.basename(fn)) && $1.to_i > greater}
        end
    else
        fns.map! {|fn| File.join(dir, fn)}
    end

    fns.each do |fn|
        run(fn, options: options)
    end
end

if __FILE__ == $0
    dir = '../stagedata'
    pattern = nil
    exclude = nil
    greater = nil
    options = {
        no_prune: false,
        use_bfs: false,
        timeout: nil,
    }
    opt = OptionParser.new
    opt.on('--no-prune') {|_| options[:no_prune] = true}
    opt.on('--bfs') {|_| options[:use_bfs] = true}
    opt.on('--timeout=seconds') {|s| options[:timeout] = s.to_f}
    opt.on('-d', '--dir=Directory') {|s| dir = s}
    opt.on('-p', '--pattern=regexp') {|s| pattern = Regexp.new(s)}
    opt.on('-e', '--exclude=regexp') {|s| exclude = Regexp.new(s)}
    opt.on('-g', '--greater=num') {|s| greater = s.to_i}
    opt.parse!(ARGV)

    main(ARGV.dup, dir, pattern, exclude, greater, options)
end
