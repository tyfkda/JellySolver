package jelly;

import java.util.Map;

public class Const {
    public static final char EMPTY_CHAR = '.';
    public static final char WALL_CHAR = '#';
    public static final String RE_JELLY_CHARS = "[RBYG]";
    public static final char BLACK = '@';

    public static final Map<Character, int[]> DIRS = Map.of(
        '<', new int[]{-1, 0},
        '>', new int[]{1, 0},
        '^', new int[]{0, -1},
        'v', new int[]{0, 1}
    );
}
