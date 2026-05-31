package jelly;

public record Point(int x, int y) implements Comparable<Point> {
    @Override
    public int compareTo(Point other) {
        if (this.y != other.y) {
            return Integer.compare(this.y, other.y);
        }
        return Integer.compare(this.x, other.x);
    }
}
