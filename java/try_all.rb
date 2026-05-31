#!/usr/bin/env ruby

require 'open3'
require 'optparse'
require 'timeout'

def run(fn, options: {})
    print "#{Time.now.strftime('%H:%M:%S')} #{File.basename(fn)}: "

    command = [
        'java', 'Main', '--quiet',
        options[:no_prune] ? '--no-prune' : nil,
        options[:use_bfs] ? '--bfs' : nil,
        fn,
    ].compact

    pid = nil
    out = ""
    err = ""
    status = nil
    start_time = Time.now

    begin
        if options[:timeout]
            Timeout.timeout(options[:timeout]) do
                Open3.popen3(*command) do |stdin, stdout, stderr, wait_thr|
                    pid = wait_thr.pid
                    out = stdout.read
                    err = stderr.read
                    status = wait_thr.value
                end
            end
        else
            Open3.popen3(*command) do |stdin, stdout, stderr, wait_thr|
                out = stdout.read
                err = stderr.read
                status = wait_thr.value
            end
        end
    rescue Timeout::Error
        if pid
            begin
                Process.kill("KILL", pid)
                Process.wait(pid)
            rescue Errno::ESRCH, Errno::ECHILD
            end
        end
        elapsed = Time.now - start_time
        puts "Timeout (killed after #{sprintf("%.3f", elapsed)}s)"
        return
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
    # Compile
    puts "Compiling Java files..."
    system("javac Main.java jelly/*.java")
    unless $?.success?
        puts "Compilation failed."
        exit(1)
    end

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
