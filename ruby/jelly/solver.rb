module Jelly
    class Solver
        def solve(stage, &block)
            enumerate_next(stage, &block)
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
            return nil unless stage.can_move?(jelly, dx, 0)

            i = stage.jellies.index(jelly)
            cloned = stage.jellies.dup()
            cloned[i] = Jelly.new(jelly.x + dx, jelly.y, jelly.color, jelly.shape)
            updated = Stage.new(stage.wall_lines, cloned)

            fall_info = nil
            while (fall_info = updated.free_fall(fall_info))
                ;
            end
            updated.merge_jellies()
            return updated
        end
    end
end
