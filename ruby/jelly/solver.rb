module Jelly
    class Solver
        attr_reader :check_count

        def initialize(quiet: false)
            @quiet = quiet
        end

        def solve(stage, &block)
            stage.freeze()
            key = stage.node_key()
            que = []
            que << [stage, key]
            nodes = {}
            nodes[key] = [nil, nil]
            check_count = 0

            until que.empty?
                stage, key = que.shift
                check_count += 1

                unless @quiet
                    $stderr.print "\rCheck=#{check_count}, left=#{que.size}\x1b[0K"
                end
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
                        next_stage.freeze()
                        que << [next_stage, next_key]
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
            stage.jellies.each do |jelly|
                2.times do |j|
                    dx = j * 2 - 1
                    updated = Solver.move_jelly(stage, jelly, dx)
                    unless updated.nil?
                        top = jelly.shape.positions.first
                        move = [jelly.x + top[0], jelly.y + top[1], dx]
                        block.call(updated, move)
                    end
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
    end
end
