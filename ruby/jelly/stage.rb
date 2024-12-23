require_relative 'const'

module Jelly
    class Stage
        attr_accessor :wall_lines, :jellies

        def initialize(wall_lines, jellies)
            @wall_lines = wall_lines
            @jellies = jellies
        end

        def can_move?(jelly, dx, dy)
            newx = jelly.x + dx
            newy = jelly.y + dy
            # 壁との衝突判定
            jelly.shape.lines.each_with_index do |line, i|
                if (@wall_lines[newy + i] & (line << newx)) != 0
                    return false
                end
            end
            # 他のゼリーとの衝突判定
            @jellies.each do |other|
                next if other.eql?(jelly)
                if other.overlap?(jelly, newx, newy)
                    return false
                end
            end
            return true
        end

        def free_fall(fall_info = nil)
            if fall_info.nil?
                wall_lines = @wall_lines.dup()
                jellies = @jellies.sort_by {|jelly| -(jelly.y + jelly.shape.h - 1)}
            else
                wall_lines, jellies = fall_info
            end

            while true
                i = 0
                again = false
                while i < jellies.length
                    jelly = jellies[i]
                    # 壁に接地しているか？
                    grounded = false
                    jelly.shape.lines.each_with_index do |line, j|
                        if wall_lines[jelly.y + j + 1] & (line << jelly.x) != 0
                            grounded = true
                            break
                        end
                    end
                    if grounded
                        jelly.shape.lines.each_with_index do |line, j|
                            wall_lines[jelly.y + j] |= (line << jelly.x)
                        end
                        jellies.delete_at(i)
                        again = true
                        next
                    end
                    i += 1
                end
                break unless again
            end
            return nil if jellies.empty?

            jellies.each_with_index do |jelly, i|
                index = @jellies.find_index(jelly)
                raise "jelly not found" if index.nil?
                jelly = jelly.dup()
                @jellies[index] = jellies[i] = jelly
                jelly.y += 1
            end
            return fall_info || [wall_lines, jellies]
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
