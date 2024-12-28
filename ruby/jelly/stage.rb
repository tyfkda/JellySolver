require_relative 'const'

module Jelly
    class Stage
        attr_accessor :wall_lines, :jellies
        attr_accessor :distance

        def initialize(wall_lines, jellies)
            @wall_lines = wall_lines
            @jellies = jellies
        end

        def height()
            return @wall_lines.length
        end

        def width()
            return @wall_lines.first.to_s(2).length
        end

        def solved?()
            h = Set.new()
            @jellies.each do |jelly|
                next if jelly.color == BLACK
                return false if h.include?(jelly.color)
                h.add(jelly.color)
            end
            return true
        end

        def freeze()
            # ブロックはすでに固定済みと仮定
            super()
            @jellies.each(&:freeze)
            @jellies.freeze()
            return self
        end

        def dup()
            jellies = @jellies.map(&:dup)
            return Stage.new(@wall_lines, jellies)
        end

        # 動かせるなら、動かした結果のStageを返す
        # 自分がfreezeされている場合新しいStageを生成、されていなければ自分自身を書き換える
        def can_move?(jelly, dx, dy)
            return nil if jelly.locked
            moves = can_move_recur(jelly, dx, dy)
            return nil if moves.nil?

            return move_jellies(moves, dx, dy)
        end

        def move_jellies(moves, dx, dy)
            if frozen?
                jellies = @jellies.dup()  # jelliesの中身はfrozenのままとしておく
                updated = Stage.new(@wall_lines, jellies)
                return updated.move_jellies(moves, dx, dy)
            end

            moves.each do |jelly|
                if jelly.frozen?
                    index = @jellies.find_index(jelly)
                    raise "jelly not found" if index.nil?
                    jelly = jelly.dup()
                    @jellies[index] = jelly
                end
                jelly.x += dx
                jelly.y += dy
            end
            return self
        end

        # 対象のゼリーが動かせるなら、動かした結果のゼリーの集合を返す
        def can_move_recur(jelly, dx, dy, moves = nil)
            newx = jelly.x + dx
            newy = jelly.y + dy
            # 壁との衝突判定
            jelly.shape.lines.each_with_index do |line, i|
                if (@wall_lines[newy + i] & (line << newx)) != 0
                    return nil
                end
            end

            moves ||= Set.new()
            moves.add(jelly)
            # 他のゼリーとの衝突判定
            @jellies.each do |other|
                next if moves.include?(other)
                next unless other.overlap?(jelly, newx, newy)
                return nil if other.locked
                moves = can_move_recur(other, dx, dy, moves)
                return nil if moves.nil?
            end
            return moves
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
                    grounded = jelly.locked
                    unless grounded
                        jelly.shape.lines.each_with_index do |line, j|
                            if wall_lines[jelly.y + j + 1] & (line << jelly.x) != 0
                                grounded = true
                                break
                            end
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
                if jelly.frozen?
                    index = @jellies.find_index(jelly)
                    raise "jelly not found" if index.nil?
                    jelly = jelly.dup()
                    @jellies[index] = jellies[i] = jelly
                end
                jelly.y += 1
            end
            return fall_info || [wall_lines, jellies]
        end

        def merge_jellies()
            # frozenじゃないjellyを前に移動
            i = 0
            j = @jellies.length - 1
            while true
                while i < j && !@jellies[i].frozen?
                    i += 1
                end
                while i < j && @jellies[j].frozen?
                    j -= 1
                end
                break if i >= j
                @jellies[i], @jellies[j] = @jellies[j], @jellies[i]
                i += 1
                j -= 1
            end

            # その状態で前から辿ると、frozenじゃないjellyにマージされる
            @jellies.each_with_index do |jelly, i|
                next if jelly.nil? || jelly.color == BLACK

                j = i + 1
                while j < @jellies.length
                    other = @jellies[j]
                    if other.nil? || other.color != jelly.color
                        j += 1
                        next
                    end
                    if jelly.adjacent?(other)
                        raise "Invalid" if jelly.frozen?
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

        # クリア状態までの距離を推定
        def estimate_distance()
            color_jellies = Hash.new {|h, k| h[k] = []}
            @jellies.each do |jelly|
                next if jelly.color == BLACK
                color_jellies[jelly.color] << jelly
            end

            return color_jellies.values.inject(0) do |acc, array|
                if array.length < 2
                    acc
                else
                    jl = array.min_by {|jelly| jelly.x}
                    jr = array.max_by {|jelly| jelly.x + jelly.shape.w}
                    acc + [jr.x - (jl.x + jl.shape.w), 1].max
                end
            end
        end

        def make_lines()
            lines = @wall_lines.map do |line|
                line.to_s(2).reverse.gsub('0', EMPTY_CHAR).gsub('1', WALL_CHAR)
            end
            @jellies.each do |jelly|
                c = jelly.color
                if c == BLACK
                    c = jelly.black_char
                else
                    c = c.downcase if jelly.locked
                end
                jelly.shape.positions.each do |pos|
                    lines[pos[1] + jelly.y][pos[0] + jelly.x] = c
                end
            end
            return lines
        end

        def node_key()
            # return @jellies.sort()
            return @jellies.sort().hash  # 衝突しないことを祈る
        end
    end
end
