#! /usr/bin/env ruby

require 'open3'

def run(fn, options: {})
    print "#{Time.now.strftime('%H:%M:%S')} #{fn}: "

    command = [
        'ruby', 'main.rb', '--quiet',
        options[:no_prune] ? '--no-prune' : nil,
        options[:use_bfs] ? '--bfs' : nil,
        fn,
    ].compact.join(' ')
    out, err, status = Open3.capture3(command)
    unless status.exitstatus == 0
        puts "Failed"
    else
        if /Steps=(\d+), check=(\d+), elapsed=(\d+\.\d+)s/ =~ out
            steps = $1.to_i
            check = $2.to_i
            elapsed = $3.to_f
            puts "elapsed=#{sprintf("%.3f", elapsed)}s"
        else
            puts "Result extraction failed"
        end
    end
end

def main(fns, dir, pattern, exclude, greater, options)
    if fns.empty?
        fns = Dir.glob("#{dir}/*")
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
    require 'optparse'

    dir = '.'
    pattern = nil
    exclude = nil
    pattern = nil
    greater = nil
    options = {
        no_prune: false,
        use_bfs: false,
        # quiet: true,
    }
    opt = OptionParser.new
    opt.on('--no-prune') {|_| options[:no_prune] = true}
    opt.on('--bfs') {|_| options[:use_bfs] = true}
    # opt.on('--quiet') {|_| options[:quiet] = true}
    opt.on('-d', '--dir=Directory') {|s| dir = s}
    opt.on('-p', '--pattern=regexp') {|s| pattern = Regexp.new(s)}
    opt.on('-e', '--exclude=regexp') {|s| exclude = Regexp.new(s)}
    opt.on('-g', '--greater=num') {|s| greater = s.to_i}
    opt.parse!(ARGV)

    main(ARGV.dup, dir, pattern, exclude, greater, options)
end
