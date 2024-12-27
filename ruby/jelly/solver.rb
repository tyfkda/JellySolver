require_relative 'pqueue'

module Jelly
    class Solver
        attr_reader :check_count

        def initialize(no_prune: false, use_bfs: false, quiet: false)
            @no_prune = no_prune
            @use_bfs = use_bfs
            @quiet = quiet
        end

        def solve(stage, &block)
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
                next if unsolvable?(stage)
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

            fall_info = nil
            while (fall_info = updated.free_fall(fall_info))
                ;
            end
            updated.merge_jellies()
            return updated
        end

        def unsolvable?(stage)
            return false if @constraints.nil?

            color_heights = Hash.new(0)
            stage.jellies.each do |jelly|
                next if jelly.color == BLACK || jelly.locked || !@constraints.has_key?(jelly.color)
                color_heights[jelly.color] += jelly.shape.h
            end

            stage.jellies.each do |jelly|
                next if jelly.color == BLACK || jelly.locked || !@constraints.has_key?(jelly.color)
                return true if jelly.y > @constraints[jelly.color] + color_heights[jelly.color]
            end
            return false
        end

        def detect_constraint(stage)
            constraints = {}

            height = stage.height
            width = stage.width
            maxy = height - 1
            while true
                break unless stage.wall_lines[maxy] == (1 << width) - 1
                maxy -= 1
            end

            stage.jellies.sort do |a, b|
                a.y != b.y ? a.y <=> b.y : a.x <=> b.x
            end.each do |jelly|
                break if jelly.y >= maxy - 1
                next if jelly.color == BLACK || !jelly.locked
                if !constraints.has_key?(jelly.color) || constraints[jelly.color] > jelly.y + jelly.shape.h
                    constraints[jelly.color] = jelly.y + jelly.shape.h - 1
                end
            end

            @constraints = constraints.size > 0 ? constraints : nil
        end
    end
end
