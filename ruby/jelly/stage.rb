require_relative 'const'

module Jelly
    class Stage
        attr_accessor :wall_lines, :jellies

        def initialize(wall_lines, jellies)
            @wall_lines = wall_lines
            @jellies = jellies
        end

        def merge_jellies()
            @jellies.each_with_index do |jelly, i|
                next if jelly.nil?

                j = i + 1
                while j < @jellies.length
                    other = @jellies[j]
                    if other.nil? || other.color != jelly.color
                        j += 1
                        next
                    end
                    if jelly.adjacent?(other)
                        jelly = jellies[i] = jelly.dup()
                        jelly.merge(other)
                        @jellies[j] = nil
                        # Try again.
                        j = i
                    end
                    j += 1
                end
            end
            @jellies.compact!
        end

        def make_lines()
            lines = @wall_lines.map do |line|
                line.to_s(2).reverse.gsub('0', EMPTY_CHAR).gsub('1', WALL_CHAR)
            end
            @jellies.each do |jelly|
                jelly.shape.positions.each do |pos|
                    lines[pos[1] + jelly.y][pos[0] + jelly.x] = jelly.color
                end
            end
            return lines
        end
    end
end
