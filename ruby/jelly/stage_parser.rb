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

            stage = Stage.new(wall_lines, jellies)
            stage.merge_jellies()
            return stage
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
