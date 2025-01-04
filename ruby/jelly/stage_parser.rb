require_relative 'const'
require_relative 'stage'

module Jelly
    class StageParser
        def parse(f)
            stage_array = []
            while line = f.gets
                break if line == "\n"
                stage_array << line.chomp.chars
            end

            width = stage_array[0].length + 2
            height = stage_array.length + 2

            wall_lines = []
            wall_lines << (1 << width) - 1
            jellies = []
            shape1 = JellyShape.register_shape([[0, 0]])
            stage_array.each_with_index do |row, y|
                line_bits = 1 | (1 << (width - 1))
                row.each_with_index do |cell, x|
                    c = cell.upcase
                    if RE_JELLY_CHARS.match?(c)
                        color = c
                        locked = c != cell
                        single_jelly = Jelly.new(x + 1, y + 1, color, shape1, locked)
                        jellies << single_jelly
                        next
                    end

                    case cell
                    when WALL_CHAR
                        line_bits |= 1 << (x + 1)
                    when '@', '*', '$', '%'
                        black_block = parse_black_block(stage_array, x, y)
                        jellies << black_block
                    when EMPTY_CHAR
                        # Empty
                    else
                        $stderr.puts("Unknown cell: '#{cell}' at (#{x}, #{y})")
                        exit(1)
                    end
                end
                wall_lines << line_bits
            end
            wall_lines << (1 << width) - 1
            wall_lines.freeze()

            extra = parse_extra(f, width, height, wall_lines, jellies)
            extra[:links]&.each do |link|
                top = link.shift
                link.each do |jelly|
                    top.link(jelly)
                    top = jelly
                end
            end

            stage = Stage.new(wall_lines, jellies, hiddens: extra[:hiddens])
            stage.merge_jellies()
            return stage
        end

        def parse_extra(f, width, height, wall_lines, jellies)
            links = []
            hiddens = []
            while line = f.gets
                case line.chomp
                when %r!^//!
                    # Comment
                    next
                when /^link\s+(\d+),(\d+),([<>^v])$/
                    x = $1.to_i
                    y = $2.to_i
                    dir = $3
                    if x >= 1 && x < width - 1 || y >= 1 || y < height - 1 || DIRS.key?(dir)
                        d = DIRS[dir]
                        jelly = jellies.find {|jelly| jelly.occupy_position?(x, y)}
                        dest = jellies.find {|jelly| jelly.occupy_position?(x + d[0], y + d[1])}
                        if jelly && dest
                            done = false
                            links.each do |link|
                                if link.include?(jelly)
                                    link << dest
                                    done = true
                                    break
                                elsif link.include?(dest)
                                    link << jelly
                                    done = true
                                    break
                                end
                            end
                            links << [jelly, dest] unless done
                            next
                        end
                    end
                when /^hidden\s+(\d+),(\d+),(#{RE_JELLY_CHARS}),([<>^v])$/
                    x = $1.to_i
                    y = $2.to_i
                    color = $3
                    dir = $4
                    d = DIRS[dir]
                    hidden = {x: x, y: y, color: color, dx: d[0], dy: d[1], jelly: nil}
                    jelly = jellies.find {|jelly| jelly.occupy_position?(x, y)}
                    unless jelly.nil?
                        hidden[:x] -= jelly.x
                        hidden[:y] -= jelly.y
                        hidden[:jelly] = jelly
                        jelly.add_hidden(hidden)
                    end
                    hiddens << hidden
                    next
                end
                raise "Invalid format: #{line}"
            end

            links = nil if links.empty?
            hiddens = nil if hiddens.empty?

            return {
                links: links,
                hiddens: hiddens,
            }
        end

        def parse_black_block(stage_array, x, y)
            h = stage_array.length
            w = stage_array[0].length
            c = stage_array[y][x]
            unchecked = [[x, y]]
            positions = []
            minx = x
            miny = y
            dirs = [[-1, 0], [1, 0], [0, -1], [0, 1]]
            while unchecked.length > 0
                x, y = unchecked.shift
                next if stage_array[y][x] != c
                stage_array[y][x] = '.'
                positions << [x, y]
                minx = [minx, x].min
                miny = [miny, y].min
                dirs.each do |dx, dy|
                    xx = x + dx
                    yy = y + dy
                    next if xx < 0 || yy < 0 || xx >= w || yy >= h
                    unchecked << [xx, yy]
                end
            end
            positions.map! {|pos| [pos[0] - minx, pos[1] - miny]}
            shape = JellyShape.register_shape(positions)
            color = BLACK  # c
            black_block = Jelly.new(minx + 1, miny + 1, color, shape)
            black_block.black_char = c
            return black_block
        end
    end
end
