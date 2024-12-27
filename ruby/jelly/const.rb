module Jelly
    EMPTY_CHAR = '.'
    WALL_CHAR = '#'
    RE_JELLY_CHARS = /[RBYG]/
    BLACK = '@'

    DIRS = {
        '<' => [-1, 0],
        '>' => [1, 0],
        '^' => [0, -1],
        'v' => [0, 1],
    }
end
