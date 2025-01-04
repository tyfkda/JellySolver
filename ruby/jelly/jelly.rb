module Jelly
    class JellyShape
        @@shapes = Hash.new()

        def self.register_shape(positions)
            positions.sort!
            positions.freeze()
            unless @@shapes.has_key?(positions)
                shape = JellyShape.new(positions)
                shape.freeze()
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

        def occupy_position?(x, y)
            return @positions.include?([x, y])
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

        def hash()
            return @positions.hash
        end

        def eql?(other)
            return @positions == other.positions
        end
    end

    class Jelly
        attr_accessor :x, :y, :color, :shape
        attr_accessor :locked
        attr_accessor :black_char
        attr_accessor :link_prev, :link_next
        attr_accessor :hiddens

        def initialize(x, y, color, shape, locked = false)
            @x = x
            @y = y
            @color = color
            @shape = shape
            @locked = locked
            @link_prev = @link_next = nil
            @hiddens = nil
        end

        def occupy_position?(x, y)
            return @shape.occupy_position?(x - @x, y - @y)
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
            # マージのみ、otherがリンクを形成していてもなにもしない
            dx = other.x - @x
            dy = other.y - @y
            @x = [@x, other.x].min
            @y = [@y, other.y].min
            @shape = @shape.concatenated(other.shape, dx, dy)
            @locked ||= other.locked
        end

        def link(other)
            @link_prev = @link_next = self if @link_next.nil?
            other.link_prev = other.link_next = other if other.link_next.nil?

            next1 = @link_next
            prev2 = other.link_prev

            @link_next = other
            next1.link_prev = prev2
            other.link_prev = self
            prev2.link_next = next1
        end

        def contains_link?(other)
            return false if @link_next.nil?
            q = self
            while (q = q.link_next) != self
                return true if q == other
            end
            return false
        end

        def add_hidden(hidden)
            @hiddens ||= []
            hidden.freeze()
            @hiddens << hidden
        end

        def remove_hidden(x, y)
            i = @hiddens.find_index {|hidden| hidden[:x] == x && hidden[:y] == y}
            unless i.nil?
                @hiddens.delete_at(i)
                @hiddens = nil if @hiddens.empty?
            end
        end

        def freeze()
            @hiddens.freeze() unless @hiddens.nil?
            super()
        end

        # frozen解除：複製したJellyを返す
        # リンクがある場合、それらも複製する
        def unfrozen()
            return self unless frozen?

            if @link_next.nil?
                cloned = self.dup()
                cloned.hiddens = @hiddens.dup() unless @hiddens.nil?
                return cloned
            end

            jelly = self
            result = nil
            while true
                cloned = jelly.dup()
                cloned.hiddens = jelly.hiddens.dup() unless jelly.hiddens.nil?
                cloned.link_next = cloned.link_prev = nil
                result.link(cloned) unless result.nil?
                result = cloned

                jelly = jelly.link_next
                break if jelly == self
            end
            return result.link_next
        end

        def inspect
            return "#<Jelly: x=#{@x}, y=#{@y}, color=#{@black_char || @color}, shape=#{@shape.inspect}#{@locked ? ' locked' : ''}#{@link_next ? ' link' : ''}#{@hiddens ? " hiddens=#{@hiddens.length}" : ''}}>"
        end

        def hash()
            return [@x, @y, @color, @shape.object_id, @hiddens].hash  # shapeが同じ形のものは同じオブジェクトなので、object_idで代用
        end

        def eql?(other)
            return @x == other.x && @y == other.y && @color == other.color &&
                   @shape == other.shape && @hiddens.hash == other.hiddens.hash
        end

        def <=>(other)
            return @y <=> other.y if @y != other.y
            return @x <=> other.x if @x != other.x
            return @shape.h <=> other.shape.h if @shape.h != other.shape.h
            @shape.w <=> other.shape.w if @shape.w != other.shape.w
        end
    end
end
