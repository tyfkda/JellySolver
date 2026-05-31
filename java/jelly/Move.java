package jelly;

public record Move(int x, int y, int dx) {
    @Override
    public String toString() {
        return "[" + x + ", " + y + ", " + dx + "]";
    }
}
