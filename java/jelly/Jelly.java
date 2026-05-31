package jelly;

import java.util.*;

public class Jelly implements Comparable<Jelly> {
    public int x;
    public int y;
    public char color;
    public JellyShape shape;
    public boolean locked;
    public Character blackChar; // 黒ブロック時の元の文字
    public Jelly linkPrev;
    public Jelly linkNext;
    public List<Hidden> hiddens;
    private boolean frozen;

    public Jelly(int x, int y, char color, JellyShape shape, boolean locked) {
        this.x = x;
        this.y = y;
        this.color = color;
        this.shape = shape;
        this.locked = locked;
        this.linkPrev = null;
        this.linkNext = null;
        this.hiddens = null;
        this.frozen = false;
    }

    public boolean isFrozen() {
        return frozen;
    }

    public void freeze() {
        this.frozen = true;
    }

    public boolean occupyPosition(int px, int py) {
        return shape.occupyPosition(px - x, py - y);
    }

    private static int shiftLeft(int val, int shift) {
        if (shift >= 0) {
            return val << shift;
        } else {
            return val >>> -shift;
        }
    }

    public boolean adjacent(Jelly other) {
        if (this.x + this.shape.getW() < other.x || other.x + other.shape.getW() < this.x ||
            this.y + this.shape.getH() < other.y || other.y + other.shape.getH() < this.y) {
            return false;
        }

        int y0 = Math.max(this.y - 1, other.y);
        int y1 = Math.min(this.y + this.shape.getH() + 1, other.y + other.shape.getH());
        int dx = other.x - (this.x - 1);

        for (int y = y0; y < y1; y++) {
            int thisAdj = this.shape.getAdjacentLines()[y - (this.y - 1)];
            int otherLine = other.shape.getLines()[y - other.y];
            if ((thisAdj & shiftLeft(otherLine, dx)) != 0) {
                return true;
            }
        }
        return false;
    }

    public boolean overlap(Jelly other, int newx, int newy) {
        if (this.x + this.shape.getW() <= newx || newx + other.shape.getW() <= this.x) {
            return false;
        }

        int y0 = Math.max(this.y, newy);
        int y1 = Math.min(this.y + this.shape.getH(), newy + other.shape.getH());

        for (int y = y0; y < y1; y++) {
            int thisLine = this.shape.getLines()[y - this.y];
            int otherLine = other.shape.getLines()[y - newy];
            if ((shiftLeft(thisLine, this.x) & shiftLeft(otherLine, newx)) != 0) {
                return true;
            }
        }
        return false;
    }

    public void merge(Jelly other) {
        assert !frozen : "Cannot merge into a frozen Jelly";
        int dx = other.x - this.x;
        int dy = other.y - this.y;
        this.x = Math.min(this.x, other.x);
        this.y = Math.min(this.y, other.y);
        this.shape = this.shape.concatenated(other.shape, dx, dy);
        this.locked = this.locked || other.locked;
    }

    public void link(Jelly other) {
        assert !frozen : "Cannot modify links of a frozen Jelly";
        if (this.linkNext == null) {
            this.linkPrev = this;
            this.linkNext = this;
        }
        if (other.linkNext == null) {
            other.linkPrev = other;
            other.linkNext = other;
        }

        Jelly next1 = this.linkNext;
        Jelly prev2 = other.linkPrev;

        this.linkNext = other;
        next1.linkPrev = prev2;
        other.linkPrev = this;
        prev2.linkNext = next1;
    }

    public boolean containsLink(Jelly other) {
        if (this.linkNext == null) {
            return false;
        }
        Jelly q = this;
        while ((q = q.linkNext) != this) {
            if (q == other) {
                return true;
            }
        }
        return false;
    }

    public void addHidden(Hidden hidden) {
        assert !frozen : "Cannot add hidden to a frozen Jelly";
        if (this.hiddens == null) {
            this.hiddens = new ArrayList<>();
        }
        this.hiddens.add(hidden);
    }

    public void removeHidden(int hx, int hy) {
        assert !frozen : "Cannot remove hidden from a frozen Jelly";
        if (this.hiddens == null) return;
        int index = -1;
        for (int i = 0; i < this.hiddens.size(); i++) {
            Hidden h = this.hiddens.get(i);
            if (h.x == hx && h.y == hy) {
                index = i;
                break;
            }
        }
        if (index != -1) {
            this.hiddens.remove(index);
            if (this.hiddens.isEmpty()) {
                this.hiddens = null;
            }
        }
    }

    public Jelly shallowCopy() {
        Jelly cloned = new Jelly(this.x, this.y, this.color, this.shape, this.locked);
        cloned.blackChar = this.blackChar;
        return cloned;
    }

    public Jelly unfrozen() {
        if (!this.frozen) {
            return this;
        }

        if (this.linkNext == null) {
            Jelly cloned = this.shallowCopy();
            cloned.frozen = false;
            if (this.hiddens != null) {
                cloned.hiddens = new ArrayList<>();
                for (Hidden h : this.hiddens) {
                    Hidden hCopy = h.copy();
                    hCopy.jelly = cloned;
                    cloned.hiddens.add(hCopy);
                }
            }
            return cloned;
        }

        Map<Jelly, Jelly> cloneMap = new HashMap<>();
        Jelly curr = this;
        do {
            Jelly cloned = curr.shallowCopy();
            cloned.frozen = false;
            if (curr.hiddens != null) {
                cloned.hiddens = new ArrayList<>();
                for (Hidden h : curr.hiddens) {
                    Hidden hCopy = h.copy();
                    hCopy.jelly = cloned;
                    cloned.hiddens.add(hCopy);
                }
            }
            cloneMap.put(curr, cloned);
            curr = curr.linkNext;
        } while (curr != this);

        curr = this;
        do {
            Jelly cloned = cloneMap.get(curr);
            cloned.linkNext = cloneMap.get(curr.linkNext);
            cloned.linkPrev = cloneMap.get(curr.linkPrev);

            if (cloned.hiddens != null) {
                for (Hidden h : cloned.hiddens) {
                    if (h.jelly != null && cloneMap.containsKey(h.jelly)) {
                        h.jelly = cloneMap.get(h.jelly);
                    }
                }
            }
            curr = curr.linkNext;
        } while (curr != this);

        return cloneMap.get(this);
    }

    @Override
    public int compareTo(Jelly other) {
        if (this.y != other.y) {
            return Integer.compare(this.y, other.y);
        }
        if (this.x != other.x) {
            return Integer.compare(this.x, other.x);
        }
        if (this.shape.getH() != other.shape.getH()) {
            return Integer.compare(this.shape.getH(), other.shape.getH());
        }
        return Integer.compare(this.shape.getW(), other.shape.getW());
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        Jelly jelly = (Jelly) o;
        if (x != jelly.x || y != jelly.y || color != jelly.color || locked != jelly.locked) {
            return false;
        }
        if (!Objects.equals(shape, jelly.shape)) {
            return false;
        }
        return Objects.equals(hiddens, jelly.hiddens);
    }

    @Override
    public int hashCode() {
        return Objects.hash(x, y, color, shape, hiddens);
    }

    @Override
    public String toString() {
        return "Jelly{x=" + x + ", y=" + y + ", color=" + (blackChar != null ? blackChar : color) + 
               ", shape=" + shape + (locked ? " locked" : "") + (linkNext != null ? " linked" : "") +
               (hiddens != null ? " hiddens=" + hiddens.size() : "") + "}";
    }
}
