module Jelly
    class JellyShape
        @@shapes = Hash.new()

        def self.register_shape(positions)
            positions.sort!
            unless @@shapes.has_key?(positions)
                shape = JellyShape.new(positions)
                @@shapes[positions] = shape
            end
            return @@shapes[positions]
        end

        attr_accessor :positions
        attr_accessor :w, :h
        attr_accessor :lines, :adjacent_lines  # bitboard

        def initialize(positions = [])
            @positions = positions
            @w = positions.map {|pos| pos[0]}.max + 1
            @h = positions.map {|pos| pos[1]}.max + 1

            lines = Array.new(@h) { 0 }
            @positions.each do |pos|
                lines[pos[1]] |= 1 << pos[0]
            end
            @lines = lines

            adjacent_lines = Array.new(@h + 2) { 0 }
            lines.each_with_index do |line, i|
                adjacent_lines[i    ] |= line << 1
                adjacent_lines[i + 1] |= line | (line << 2)
                adjacent_lines[i + 2] |= line << 1
            end
            @adjacent_lines = adjacent_lines
        end

        def concatenated(shape, dx, dy)
            positions = @positions.map(&:dup)
            if dx < 0
                positions.each do |pos|
                    pos[0] -= dx
                end
                dx = 0
            end
            if dy < 0
                positions.each do |pos|
                    pos[1] -= dy
                end
                dy = 0
            end

            shape.positions.each do |pos|
                positions << [pos[0] + dx, pos[1] + dy]
            end
            return JellyShape.register_shape(positions)
        end

        def inspect
            return "#<JellyShape: w=#{w},h=#{h} positions=#{@positions}>"
        end
    end

    class Jelly
        attr_accessor :x, :y, :color, :shape

        def initialize(x, y, color, shape)
            @x = x
            @y = y
            @color = color
            @shape = shape
        end

        def adjacent?(other)
            return false if (@x + @shape.w < other.x || other.x + other.shape.w < @x ||
                             @y + @shape.h < other.y || other.y + other.shape.h < @y)

            y0 = [@y - 1, other.y].max
            y1 = [@y + @shape.h + 1, other.y + other.shape.h].min
            dx = other.x - (@x - 1)
            return (y0...y1).any? do |y|
                (@shape.adjacent_lines[y - (@y - 1)] & (other.shape.lines[y - other.y] << dx)) != 0
            end
        end

        def overlap?(other, newx, newy)
            if @x + @shape.w <= newx || newx + other.shape.w <= @x
                return false
            end

            y0 = [@y, newy].max
            y1 = [@y + @shape.h, newy + other.shape.h].min
            (y0...y1).any? do |y|
                ((@shape.lines[y - @y] << @x) & (other.shape.lines[y - newy] << newx)) != 0
            end
        end

        def merge(other)
            dx = other.x - @x
            dy = other.y - @y
            @x = [@x, other.x].min
            @y = [@y, other.y].min
            @shape = @shape.concatenated(other.shape, dx, dy)
        end

        def inspect
            return "#<Jelly: x=#{@x}, y=#{@y}, color=#{@color}, shape=#{@shape.inspect}>"
        end
    end
end
