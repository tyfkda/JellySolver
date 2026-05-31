require_relative 'pqueue'
require 'thread'
require 'etc'

module Jelly
    class Solver
        attr_reader :check_count

        class SearchNode
            attr_reader :stage, :key, :step, :f_score
            def initialize(stage, key, step, use_bfs)
                @stage = stage
                @key = key
                @step = step
                @f_score = use_bfs ? 0 : (stage.distance || 0) + step
            end
        end

        class ThreadSafeQueue
            def initialize
                @q = []
                @mutex = Mutex.new
                @cond = ConditionVariable.new
            end

            def push(val)
                @mutex.synchronize do
                    @q << val
                    @cond.signal
                end
            end
            alias << push

            def pop(timeout = nil)
                @mutex.synchronize do
                    if timeout
                        limit = Time.now + timeout
                        while @q.empty?
                            remaining = limit - Time.now
                            break if remaining <= 0
                            @cond.wait(@mutex, remaining)
                        end
                    else
                        while @q.empty?
                            @cond.wait(@mutex)
                        end
                    end
                    @q.empty? ? nil : @q.shift
                end
            end

            def size
                @mutex.synchronize { @q.size }
            end

            def empty?
                @mutex.synchronize { @q.empty? }
            end
        end

        class ThreadSafePriorityQueue
            def initialize(&block)
                @pq = PriorityQueue.new(&block)
                @mutex = Mutex.new
                @cond = ConditionVariable.new
            end

            def push(val)
                @mutex.synchronize do
                    @pq << val
                    @cond.signal
                end
            end
            alias << push

            def pop(timeout = nil)
                @mutex.synchronize do
                    if timeout
                        limit = Time.now + timeout
                        while @pq.empty?
                            remaining = limit - Time.now
                            break if remaining <= 0
                            @cond.wait(@mutex, remaining)
                        end
                    else
                        while @pq.empty?
                            @cond.wait(@mutex)
                        end
                    end
                    @pq.empty? ? nil : @pq.shift
                end
            end

            def size
                @mutex.synchronize { @pq.size }
            end

            def empty?
                @mutex.synchronize { @pq.empty? }
            end
        end

        def initialize(no_prune: false, use_bfs: false, quiet: false, parallel: false)
            @no_prune = no_prune
            @use_bfs = use_bfs
            @quiet = quiet
            @parallel = parallel
        end

        def solve(stage, &block)
            if @parallel
                solve_parallel(stage, &block)
            else
                solve_sequential(stage, &block)
            end
        end

        def solve_sequential(stage, &block)
            detect_constraint(stage) unless @no_prune

            stage.distance = stage.estimate_distance() unless @use_bfs
            stage.freeze()
            key = stage.node_key()
            if @use_bfs
                que = []
            else
                que = PriorityQueue.new() {|x, y| x[0].distance + x[2] <=> y[0].distance + y[2]}
            end
            que << [stage, key, 0]
            nodes = {}
            nodes[key] = [nil, nil]
            check_count = 0

            until que.empty?
                stage, key, step = que.shift
                check_count += 1

                unless @quiet
                    $stderr.print "\rCheck=#{check_count}, left=#{que.size}\x1b[0K"
                end
                next if !@no_prune && unsolvable?(stage)
                if stage.solved?()
                    @check_count = check_count
                    moves = extract_moves(nodes, key)
                    if block.nil? || block.call(moves)
                        return moves
                    end
                end

                enumerate_next(stage) do |next_stage, move|
                    next_key = next_stage.node_key()
                    unless nodes.has_key?(next_key)
                        nodes[next_key] = [key, move]
                        next_stage.distance = next_stage.estimate_distance() unless @use_bfs
                        next_stage.freeze()
                        que << [next_stage, next_key, step + 1]
                    end
                end
            end
            @check_count = check_count
            return nil
        end

        def solve_parallel(stage, &block)
            detect_constraint(stage) unless @no_prune

            stage.distance = stage.estimate_distance() unless @use_bfs
            stage.freeze()
            key = stage.node_key()

            if @use_bfs
                que = ThreadSafeQueue.new
            else
                que = ThreadSafePriorityQueue.new {|x, y| x.f_score <=> y.f_score}
            end

            que << SearchNode.new(stage, key, 0, @use_bfs)

            nodes = {}
            nodes_mutex = Mutex.new
            nodes[key] = [nil, nil]

            check_count = 0
            check_mutex = Mutex.new

            active_workers = 0
            workers_mutex = Mutex.new

            goal_stage = nil
            goal_key = nil
            goal_mutex = Mutex.new

            num_threads = Etc.respond_to?(:nprocessors) ? Etc.nprocessors : 4
            threads = []

            num_threads.times do
                threads << Thread.new do
                    while true
                        break if goal_mutex.synchronize { goal_stage }

                        node = que.pop(0.01)

                        if node.nil?
                            is_done = false
                            workers_mutex.synchronize do
                                if active_workers == 0 && que.empty?
                                    is_done = true
                                end
                            end
                            break if is_done
                            next
                        end

                        workers_mutex.synchronize { active_workers += 1 }
                        begin
                            current_stage = node.stage
                            current_key = node.key
                            step = node.step

                            current_check = nil
                            check_mutex.synchronize do
                                check_count += 1
                                current_check = check_count
                            end

                            if !@quiet && current_check % 1000 == 0
                                $stderr.print "\rCheck=#{current_check}, left=#{que.size}\x1b[0K"
                            end

                            next if !@no_prune && unsolvable?(current_stage)

                            if current_stage.solved?
                                goal_mutex.synchronize do
                                    goal_stage = current_stage
                                    goal_key = current_key
                                end
                                break
                            end

                            enumerate_next(current_stage) do |next_stage, move|
                                next_key = next_stage.node_key()
                                added = false
                                nodes_mutex.synchronize do
                                    unless nodes.has_key?(next_key)
                                        nodes[next_key] = [current_key, move]
                                        added = true
                                    end
                                end

                                if added
                                    next_stage.distance = next_stage.estimate_distance() unless @use_bfs
                                    next_stage.freeze()
                                    que.push(SearchNode.new(next_stage, next_key, step + 1, @use_bfs))
                                end
                            end
                        ensure
                            workers_mutex.synchronize { active_workers -= 1 }
                        end
                    end
                end
            end

            threads.each(&:join)

            @check_count = check_mutex.synchronize { check_count }
            final_goal = goal_mutex.synchronize { goal_stage }
            final_key = goal_mutex.synchronize { goal_key }

            if final_goal
                moves = extract_moves(nodes, final_key)
                if block.nil? || block.call(moves)
                    return moves
                end
            end

            return nil
        end

        def extract_moves(nodes, key)
            moves = []
            while true
                prev_key, move = nodes[key]
                break unless prev_key
                moves << move
                key = prev_key
            end
            return moves.reverse!
        end

        def enumerate_next(stage, &block)
            skips = Set.new()
            stage.jellies.each do |jelly|
                next if skips.include?(jelly)
                2.times do |j|
                    dx = j * 2 - 1
                    updated = Solver.move_jelly(stage, jelly, dx)
                    unless updated.nil?
                        top = jelly.shape.positions.first
                        move = [jelly.x + top[0], jelly.y + top[1], dx]
                        block.call(updated, move)
                    end
                end

                unless jelly.link_next.nil?
                    other = jelly
                    skips.add(other) while (other = other.link_next) != jelly
                end
            end
        end

        def self.move_jelly(stage, jelly, dx)
            updated = stage.can_move?(jelly, dx, 0)
            return nil if updated.nil?

            while true
                fall_info = nil
                while (fall_info = updated.free_fall(fall_info))
                    ;
                end
                updated.merge_jellies()
                unless updated.apply_hiddens()
                    break
                end
            end
            return updated
        end

        def unsolvable?(stage)
            constraints = @constraints
            up = 0
            unless stage.hiddens.nil?
                constraints = @constraints.dup() unless @constraints.nil?
                stage.hiddens.each do |hidden|
                    up += 1 if hidden[:dy] <= 0
                    next if !hidden[:jelly].nil? || hidden[:link]
                    y, color, dy = hidden.values_at(:y, :color, :dy)
                    y += dy
                    next if y >= @maxy
                    if constraints.nil? || !constraints.has_key?(color) || constraints[color] > y
                        constraints = {} if constraints.nil?
                        constraints[color] = y
                    end
                end
            end
            return false if constraints.nil?

            color_heights = Hash.new(0)
            stage.jellies.each do |jelly|
                next if jelly.color == BLACK || jelly.locked || !constraints.has_key?(jelly.color)
                color_heights[jelly.color] += jelly.shape.h
            end

            stage.jellies.each do |jelly|
                next if jelly.color == BLACK || jelly.locked || !constraints.has_key?(jelly.color)
                return true if jelly.y - color_heights[jelly.color] - up >= constraints[jelly.color]
            end
            return false
        end

        def detect_constraint(stage)
            constraints = {}

            height = stage.height
            width = stage.width
            maxy = height - 1
            while true
                wall_line = stage.wall_lines[maxy]
                unless wall_line == (1 << width) - 1
                    vacant = (1..(width - 2)).any? do |x|
                        if (wall_line & (1 << x)) != 0
                            false
                        else
                            jelly = stage.jellies.find {|it| it.occupy_position?(x, maxy)}
                            jelly.nil? || !jelly.locked
                        end
                    end
                    break if vacant
                end
                maxy -= 1
            end

            stage.jellies.sort do |a, b|
                a.y != b.y ? a.y <=> b.y : a.x <=> b.x
            end.each do |jelly|
                break if jelly.y >= maxy
                next if jelly.color == BLACK || !jelly.locked
                y = jelly.y + jelly.shape.h

                # 下面が壁に覆われてたら下からつなげられないので、その分を補正
                walls = (0...jelly.shape.w).all? do |dx|
                    stage.wall_lines[y] & (1 << (jelly.x + dx)) != 0
                end
                y -= 1 if walls

                if !constraints.has_key?(jelly.color) || constraints[jelly.color] > y
                    constraints[jelly.color] = y
                end
            end

            stage.hiddens&.each do |hidden|
                next unless hidden[:jelly].nil? && hidden[:link]
                y, color, dy = hidden.values_at(:y, :color, :dy)
                y += dy
                next if y >= maxy
                if !constraints.has_key?(color) || constraints[color] > y
                    constraints[color] = y
                end
            end

            @constraints = constraints.size > 0 ? constraints : nil
            @maxy = maxy
        end
    end
end
