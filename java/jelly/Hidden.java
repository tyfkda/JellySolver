package jelly;

import java.util.Objects;

public class Hidden {
    public int x;
    public int y;
    public char color;
    public int dx;
    public int dy;
    public Jelly jelly; // トリガーとなる親ゼリーへの参照
    public boolean link;

    public Hidden(int x, int y, char color, int dx, int dy, Jelly jelly, boolean link) {
        this.x = x;
        this.y = y;
        this.color = color;
        this.dx = dx;
        this.dy = dy;
        this.jelly = jelly;
        this.link = link;
    }

    public Hidden copy() {
        return new Hidden(this.x, this.y, this.color, this.dx, this.dy, this.jelly, this.link);
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        Hidden hidden = (Hidden) o;
        if (x != hidden.x || y != hidden.y || color != hidden.color || dx != hidden.dx || dy != hidden.dy || link != hidden.link) {
            return false;
        }
        if (jelly == null && hidden.jelly == null) {
            return true;
        }
        if (jelly == null || hidden.jelly == null) {
            return false;
        }
        // 循環参照を回避するため、jelly の x, y, color のみで比較
        return jelly.x == hidden.jelly.x && jelly.y == hidden.jelly.y && jelly.color == hidden.jelly.color;
    }

    @Override
    public int hashCode() {
        int jellyHash = 0;
        if (jelly != null) {
            jellyHash = Objects.hash(jelly.x, jelly.y, jelly.color);
        }
        return Objects.hash(x, y, color, dx, dy, link, jellyHash);
    }

    @Override
    public String toString() {
        return "Hidden{x=" + x + ", y=" + y + ", color=" + color + ", dx=" + dx + ", dy=" + dy + ", hasJelly=" + (jelly != null) + ", link=" + link + "}";
    }
}
