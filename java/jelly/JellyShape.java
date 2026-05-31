package jelly;

import java.util.*;

public class JellyShape {
    private static final Map<List<Point>, JellyShape> shapes = new HashMap<>();

    public static synchronized JellyShape registerShape(List<Point> positions) {
        List<Point> sorted = new ArrayList<>(positions);
        Collections.sort(sorted);
        // 不変リストにしてキーとする
        List<Point> key = List.copyOf(sorted);
        if (!shapes.containsKey(key)) {
            shapes.put(key, new JellyShape(key));
        }
        return shapes.get(key);
    }

    private final List<Point> positions;
    private final int w;
    private final int h;
    private final int[] lines;
    private final int[] adjacentLines;

    private JellyShape(List<Point> positions) {
        this.positions = positions;
        int maxW = 0;
        int maxH = 0;
        for (Point p : positions) {
            if (p.x() > maxW) maxW = p.x();
            if (p.y() > maxH) maxH = p.y();
        }
        this.w = maxW + 1;
        this.h = maxH + 1;

        int[] lines = new int[this.h];
        for (Point p : positions) {
            lines[p.y()] |= 1 << p.x();
        }
        this.lines = lines;

        int[] adj = new int[this.h + 2];
        for (int i = 0; i < lines.length; i++) {
            int line = lines[i];
            adj[i] |= line << 1;
            adj[i + 1] |= line | (line << 2);
            adj[i + 2] |= line << 1;
        }
        this.adjacentLines = adj;
    }

    public List<Point> getPositions() {
        return positions;
    }

    public int getW() {
        return w;
    }

    public int getH() {
        return h;
    }

    public int[] getLines() {
        return lines;
    }

    public int[] getAdjacentLines() {
        return adjacentLines;
    }

    public boolean occupyPosition(int x, int y) {
        for (Point p : positions) {
            if (p.x() == x && p.y() == y) {
                return true;
            }
        }
        return false;
    }

    public JellyShape concatenated(JellyShape other, int dx, int dy) {
        List<Point> newPositions = new ArrayList<>();
        int offsetX = 0;
        int offsetY = 0;
        if (dx < 0) {
            offsetX = -dx;
            dx = 0;
        }
        if (dy < 0) {
            offsetY = -dy;
            dy = 0;
        }

        for (Point p : this.positions) {
            newPositions.add(new Point(p.x() + offsetX, p.y() + offsetY));
        }
        for (Point p : other.positions) {
            newPositions.add(new Point(p.x() + dx, p.y() + dy));
        }
        return registerShape(newPositions);
    }

    @Override
    public String toString() {
        return "JellyShape{w=" + w + ", h=" + h + ", positions=" + positions + "}";
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        JellyShape that = (JellyShape) o;
        return Objects.equals(positions, that.positions);
    }

    @Override
    public int hashCode() {
        return Objects.hash(positions);
    }
}
