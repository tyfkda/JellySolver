require_relative 'const'

module Jelly
    class Stage
        def self.unfrozen_jelly(jellies, jelly)
            return jelly unless jelly.frozen?

            result = jelly.unfrozen()

            # 配列も置き換える
            src = jelly
            dst = result
            while true
                i = jellies.find_index {|target| target == src}
                raise "jelly not found" if i.nil?
                jellies[i] = dst

                src = src.link_next
                dst = dst.link_next
                break if src.nil? || src == jelly
            end
            return result
        end

        def self.settle_jelly(wall_lines, jelly)
            jelly.shape.lines.each_with_index do |line, j|
                wall_lines[jelly.y + j] |= (line << jelly.x)
            end
        end

        attr_accessor :wall_lines, :jellies
        attr_accessor :hiddens
        attr_accessor :distance

        def initialize(wall_lines, jellies, hiddens: nil)
            @wall_lines = wall_lines
            @jellies = jellies
            @hiddens = hiddens  # [{x, y, color, dx, dy, jelly}]
            hiddens.each(&:freeze) unless hiddens.nil?
        end

        def freeze()
            @hiddens.freeze() unless @hiddens.nil?
            super()
        end

        def height()
            return @wall_lines.length
        end

        def width()
            return @wall_lines.first.to_s(2).length
        end

        def solved?()
            return false unless @hiddens.nil?

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
            @hiddens&.freeze()
            return self
        end

        def dup()
            return self if !frozen?

            jellies = @jellies.dup()
            jellies.each_with_index do |jelly, i|
                next unless jelly.frozen?
                if jelly.link_next.nil?
                    jellies[i] = jelly.unfrozen()
                    next
                end

                dst = jelly.unfrozen()
                src = jelly
                while true
                    i = jellies.find_index(src)
                    raise "jelly not found" unless i
                    jellies[i] = dst

                    src = src.link_next
                    dst = dst.link_next
                    break if src.nil? || src == jelly
                end
            end
            hiddens = @hiddens&.map do |hidden|
                unless hidden[:jelly].nil?
                    hidden = hidden.dup()
                    i = @jellies.find_index {|jelly| jelly == hidden[:jelly]}
                    raise "jelly not found" if i.nil?
                    raise "different" unless jellies[i].eql?(@jellies[i])
                    hidden[:jelly] = jellies[i]
                end
                hidden
            end
            return Stage.new(@wall_lines, jellies, hiddens: hiddens)
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
                updated = Stage.new(@wall_lines, jellies, hiddens: @hiddens)
                return updated.move_jellies(moves, dx, dy)
            end

            moves.each do |jelly|
                unless jelly.link_next.nil?
                    other = jelly
                    while (other = other.link_next) != jelly
                        moves.delete(other)
                    end
                end
                if jelly.frozen?
                    original = jelly
                    jelly = Stage.unfrozen_jelly(@jellies, jelly)
                    update_hiddens_for_jelly(original, jelly)
                end
                jelly.x += dx
                jelly.y += dy
                unless jelly.link_next.nil?
                    other = jelly
                    while (other = other.link_next) != jelly
                        other.x += dx
                        other.y += dy
                    end
                end
            end
            return self
        end

        def update_hiddens_for_jelly(src, dst)
            return if @hiddens.nil?

            top = src
            loop do
                unless src.hiddens.nil?
                    @hiddens = @hiddens.dup() if @hiddens.frozen?
                    i = @hiddens.find_index {|hidden| hidden[:jelly] == src}
                    unless i.nil?
                        hidden = @hiddens[i].dup()
                        hidden[:jelly] = dst
                        @hiddens[i] = hidden
                    end
                end
                src = src.link_next
                dst = dst.link_next
                break if src.nil? || src == top
            end
        end

        # 対象のゼリーが動かせるなら、動かした結果のゼリーの集合を返す
        def can_move_recur(jelly, dx, dy, moves = nil)
            # 壁との衝突判定
            other = jelly
            while true
                newx = other.x + dx
                newy = other.y + dy
                other.shape.lines.each_with_index do |line, i|
                    if (@wall_lines[newy + i] & (line << newx)) != 0
                        return nil
                    end
                end
                other = other.link_next
                break if other.nil? || other == jelly
            end

            moves ||= Set.new()
            moves.add(jelly)
            unless jelly.link_next.nil?
                other = jelly
                moves.add(other) while (other = other.link_next) != jelly
            end
            # 他のゼリーとの衝突判定
            top = jelly
            while true
                @jellies.each do |other|
                    next if moves.include?(other)
                    next unless other.overlap?(jelly, jelly.x + dx, jelly.y + dy)
                    return nil if other.locked
                    moves = can_move_recur(other, dx, dy, moves)
                    return nil if moves.nil?
                end
                jelly = jelly.link_next
                break if jelly.nil? || jelly == top
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
                        Stage.settle_jelly(wall_lines, jelly)
                        jellies.delete_at(i)
                        unless jelly.link_next.nil?
                            linked = jelly
                            while (linked = linked.link_next) != jelly
                                j = jellies.find_index(linked)
                                next if j.nil?
                                Stage.settle_jelly(wall_lines, linked)
                                jellies.delete_at(j)
                            end
                        end
                        again = true
                        next
                    end
                    i += 1
                end
                break unless again
            end
            return nil if jellies.empty?

            jellies.each do |jelly|
                if jelly.frozen?
                    unfrozen = Stage.unfrozen_jelly(@jellies, jelly)

                    src = jelly
                    dst = unfrozen
                    while true
                        index = jellies.find_index(src)
                        raise "jelly not found" if index.nil?
                        jellies[index] = dst

                        src = src.link_next
                        dst = dst.link_next
                        break if src.nil? || src == jelly
                    end

                    update_hiddens_for_jelly(jelly, unfrozen)

                    jelly = unfrozen
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
                        link_merged_jelly(jelly, other)
                        # Try again.
                        j = i
                    end
                    j += 1
                end
            end
            @jellies.compact!
        end

        def link_merged_jelly(jelly, other)
            unless other.link_next.nil?
                if !jelly.link_next.nil? && jelly.contains_link?(other)
                    # 同じリンク内でくっついた：リンクから取り除く
                    other.link_prev.link_next = other.link_next
                    other.link_next.link_prev = other.link_prev
                else
                    # other自体はマージされたので、残りのリンクを複製
                    nxt = other
                    prv = nil
                    while true
                        nxt = nxt.link_next
                        break if nxt == other
                        cloned = nxt.dup()
                        cloned.link_next = cloned.link_prev = cloned
                        prv.link(cloned) if prv
                        prv = cloned
                    end
                    nxt = prv.link_next
                    jelly.link(nxt)  # リンク

                    # リンクの更新に従って配列も更新
                    q = other
                    r = nxt
                    while (q = q.link_next) != other
                        # @jellies.replace(q, r)
                        k = @jellies.find_index(q)
                        raise "jelly not found" unless k
                        @jellies[k] = r
                        r = r.link_next
                    end
                end
            end

            # ロックを全体に反映
            if jelly.locked
                q = jelly
                q.locked = true while (q = q.link_next) != jelly && !q.nil?
            end
        end

        def apply_hiddens()
            return nil if @hiddens.nil?

            applied = nil
            i = -1
            while (i += 1) < @hiddens.length
                hidden = @hiddens[i]
                x, y, color, dx, dy, owner = hidden.values_at(:x, :y, :color, :dx, :dy, :jelly)
                unless owner.nil?
                    x += owner.x
                    y += owner.y
                end
                @jellies.each_with_index do |jelly, j|
                    next unless jelly.color == color && jelly.occupy_position?(x + dx, y + dy)
                    if apply_hidden(j, hidden)
                        @hiddens = @hiddens.dup() if @hiddens.frozen?
                        @hiddens.delete_at(i)
                        i -= 1
                        applied = self
                    end
                end
            end
            @hiddens = nil if @hiddens.empty?
            return applied
        end

        def apply_hidden(j, hidden)
            jelly = @jellies[j]
            ox = jelly.x
            oy = jelly.y

            x, y, color, dx, dy, owner, link = hidden.values_at(:x, :y, :color, :dx, :dy, :jelly, :link)
            unless owner.nil?
                x += owner.x
                y += owner.y
            end
            updated = can_move?(jelly, dx, dy)
            owner_moved = false
            if updated.nil?
                # ownerがいたら、そいつを逆向きに動かせるか試す
                return false if owner.nil?
                updated = can_move?(owner, -dx, -dy)
                return false if updated.nil?
                raise "Unexpected" unless updated == self
                if owner.frozen?
                    # ownerが複製されているはずなので、取得し直す
                    owner = @jellies.find {|other| other.x == owner.x - dx && other.y == owner.y - dy && other.color == owner.color && other.shape == owner.shape}
                    raise "owner not found" if owner.nil?
                end
                x -= dx
                y -= dy
                owner_moved = true

                if jelly.frozen?
                    jelly = Stage.unfrozen_jelly(@jellies, jelly)
                end
            else
                k = @jellies.find_index {|other| other.x == ox + dx && other.y == oy + dy && other.color == jelly.color && other.shape == jelly.shape}
                if k != j
                    puts "In apply_hidden, index different:#{j}/#{k}"
                    j = k
                    jelly = @jellies[j]
                end
            end

            raise "Unexpected" unless updated == self
            # raise "Unexpected" unless @jellies[j] == jelly
            locked = link && owner.nil?
            appeared = Jelly.new(x + dx, y + dy, color, JellyShape.register_shape([[0, 0]]), locked)
            @jellies[j].merge(appeared)

            unless owner.nil? || owner_moved
                # ownerがfreezeされていたら解凍する必要がある
                if owner.frozen?
                    raise 'Frozen' if frozen?
                    owner = Stage.unfrozen_jelly(@jellies, owner)
                end
                owner.remove_hidden(x - owner.x, y - owner.y)
                if link
                    owner.link(@jellies[j])
                end
            end
            return true
        end

        # クリア状態までの距離を推定
        def estimate_distance()
            color_jellies = Hash.new {|h, k| h[k] = []}
            @jellies.each do |jelly|
                next if jelly.color == BLACK
                color_jellies[jelly.color] << jelly
            end

            distance = color_jellies.values.inject(0) do |acc, array|
                if array.length < 2
                    acc
                else
                    jl = array.min_by {|jelly| jelly.x}
                    jr = array.max_by {|jelly| jelly.x + jelly.shape.w}
                    acc + [jr.x - (jl.x + jl.shape.w), 1].max
                end
            end

            # 隠れゼリーを考慮
            unless @hiddens.nil?
                d = @hiddens.inject(0) do |acc, hidden|
                    x, y, color, dx, dy, owner = hidden.values_at(:x, :y, :color, :dx, :dy, :jelly)
                    unless owner.nil?
                        x += owner.x
                        y += owner.y
                    end
                    # 中間にある場合には道中で回収されるものとして、端にある場合だけ考慮

                    jellies = color_jellies[color]
                    jl = jellies.min_by {|jelly| jelly.x}
                    jr = jellies.max_by {|jelly| jelly.x + jelly.shape.w}
                    if x < jl.x
                        acc + (jl.x - x)
                    elsif x >= jr.x + jr.shape.w
                        acc + (x - (jr.x + jr.shape.w))
                    else
                        acc + 1
                    end
                end
                distance += d
            end
            return distance
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
            hiddens = @hiddens&.map do |hidden|
                x, y, color, dx, dy, jelly = hidden.values_at(:x, :y, :color, :dx, :dy, :jelly)
                [x, y, color, dx, dy].hash ^ (jelly&.hash || 0)
            end
            # return [@jellies.sort(), hiddens.hash]
            return @jellies.sort().hash ^ hiddens.hash  # 衝突しないことを祈る
        end
    end
end
