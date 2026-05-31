package jelly;

import java.util.*;

public class Stage {

    public static int indexOfByReference(List<Jelly> list, Object target) {
        for (int i = 0; i < list.size(); i++) {
            if (list.get(i) == target) {
                return i;
            }
        }
        return -1;
    }

    public static Jelly unfrozenJelly(List<Jelly> jellies, Jelly jelly) {
        if (!jelly.isFrozen()) {
            return jelly;
        }

        Jelly result = jelly.unfrozen();
        Jelly src = jelly;
        Jelly dst = result;
        while (true) {
            int i = indexOfByReference(jellies, src);
            if (i == -1) {
                throw new RuntimeException("jelly not found");
            }
            jellies.set(i, dst);

            src = src.linkNext;
            dst = dst.linkNext;
            if (src == null || src == jelly) {
                break;
            }
        }
        return result;
    }

    public static void settleJelly(int[] wallLines, Jelly jelly) {
        for (int j = 0; j < jelly.shape.getLines().length; j++) {
            int line = jelly.shape.getLines()[j];
            wallLines[jelly.y + j] |= (line << jelly.x);
        }
    }

    public static class FallInfo {
        public final int[] wallLines;
        public final List<Jelly> jellies;
        public FallInfo(int[] wallLines, List<Jelly> jellies) {
            this.wallLines = wallLines;
            this.jellies = jellies;
        }
    }

    public int[] wallLines;
    public List<Jelly> jellies;
    public List<Hidden> hiddens;
    public int distance;
    private boolean frozen;
    private List<Jelly> sortedJelliesCache;
    private List<Hidden> sortedHiddensCache;

    public Stage(int[] wallLines, List<Jelly> jellies, List<Hidden> hiddens) {
        this.wallLines = wallLines;
        this.jellies = jellies;
        this.hiddens = hiddens;
        this.distance = 0;
        this.frozen = false;
        this.sortedJelliesCache = null;
        this.sortedHiddensCache = null;
    }

    public boolean isFrozen() {
        return frozen;
    }

    public Stage freeze() {
        this.frozen = true;
        for (Jelly j : jellies) {
            j.freeze();
        }

        this.sortedJelliesCache = new ArrayList<>(this.jellies);
        Collections.sort(this.sortedJelliesCache);

        if (this.hiddens != null) {
            this.sortedHiddensCache = new ArrayList<>(this.hiddens);
            this.sortedHiddensCache.sort((a, b) -> {
                if (a.x != b.x) return Integer.compare(a.x, b.x);
                if (a.y != b.y) return Integer.compare(a.y, b.y);
                if (a.color != b.color) return Character.compare(a.color, b.color);
                if (a.dx != b.dx) return Integer.compare(a.dx, b.dx);
                if (a.dy != b.dy) return Integer.compare(a.dy, b.dy);
                return Boolean.compare(a.link, b.link);
            });
        } else {
            this.sortedHiddensCache = null;
        }

        return this;
    }

    public int getHeight() {
        return wallLines.length;
    }

    public int getWidth() {
        return Integer.toBinaryString(wallLines[0]).length();
    }

    public boolean solved() {
        if (hiddens != null) {
            return false;
        }
        Set<Character> seenColors = new HashSet<>();
        for (Jelly jelly : jellies) {
            if (jelly.color == Const.BLACK) continue;
            if (seenColors.contains(jelly.color)) {
                return false;
            }
            seenColors.add(jelly.color);
        }
        return true;
    }

    public Stage dup() {
        if (!this.frozen) {
            return this;
        }

        List<Jelly> newJellies = new ArrayList<>(this.jellies);
        for (int i = 0; i < newJellies.size(); i++) {
            Jelly jelly = newJellies.get(i);
            if (!jelly.isFrozen()) {
                continue;
            }

            if (jelly.linkNext == null) {
                newJellies.set(i, jelly.unfrozen());
                continue;
            }

            Jelly dst = jelly.unfrozen();
            Jelly src = jelly;
            while (true) {
                int index = indexOfByReference(newJellies, src);
                if (index == -1) {
                    throw new RuntimeException("jelly not found during dup");
                }
                newJellies.set(index, dst);

                src = src.linkNext;
                dst = dst.linkNext;
                if (src == null || src == jelly) {
                    break;
                }
            }
        }

        List<Hidden> newHiddens = null;
        if (this.hiddens != null) {
            newHiddens = new ArrayList<>();
            for (Hidden hidden : this.hiddens) {
                if (hidden.jelly != null) {
                    Hidden hCopy = hidden.copy();
                    int oldIndex = indexOfByReference(this.jellies, hidden.jelly);
                    if (oldIndex == -1) {
                        throw new RuntimeException("jelly not found for hidden during dup");
                    }
                    hCopy.jelly = newJellies.get(oldIndex);
                    newHiddens.add(hCopy);
                } else {
                    newHiddens.add(hidden.copy());
                }
            }
        }

        Stage newStage = new Stage(this.wallLines, newJellies, newHiddens);
        newStage.distance = this.distance;
        return newStage;
    }

    public Stage canMove(Jelly jelly, int dx, int dy) {
        if (jelly.locked) return null;
        Set<Jelly> moves = canMoveRecur(jelly, dx, dy, null);
        if (moves == null) return null;
        return moveJellies(moves, dx, dy);
    }

    public Stage moveJellies(Set<Jelly> moves, int dx, int dy) {
        if (this.frozen) {
            Stage updated = new Stage(this.wallLines, new ArrayList<>(this.jellies), this.hiddens);
            return updated.moveJellies(moves, dx, dy);
        }

        Queue<Jelly> queue = new LinkedList<>(moves);
        Set<Jelly> visited = new HashSet<>();
        while (!queue.isEmpty()) {
            Jelly jelly = queue.poll();
            if (visited.contains(jelly)) {
                continue;
            }
            visited.add(jelly);

            if (jelly.linkNext != null) {
                Jelly other = jelly;
                while ((other = other.linkNext) != jelly) {
                    visited.add(other);
                }
            }

            if (jelly.isFrozen()) {
                Jelly original = jelly;
                jelly = unfrozenJelly(this.jellies, jelly);
                updateHiddensForJelly(original, jelly);
            }
            jelly.x += dx;
            jelly.y += dy;
            if (jelly.linkNext != null) {
                Jelly other = jelly;
                while ((other = other.linkNext) != jelly) {
                    other.x += dx;
                    other.y += dy;
                }
            }
        }
        return this;
    }

    private void updateHiddensForJelly(Jelly src, Jelly dst) {
        if (this.hiddens == null) return;
        Jelly top = src;
        Jelly currSrc = src;
        Jelly currDst = dst;
        do {
            if (currSrc.hiddens != null) {
                this.hiddens = new ArrayList<>(this.hiddens);
                for (int i = 0; i < this.hiddens.size(); i++) {
                    Hidden hidden = this.hiddens.get(i);
                    if (hidden.jelly == currSrc) {
                        Hidden newHidden = hidden.copy();
                        newHidden.jelly = currDst;
                        this.hiddens.set(i, newHidden);
                    }
                }
            }
            currSrc = currSrc.linkNext;
            currDst = currDst.linkNext;
        } while (currSrc != null && currSrc != top);
    }

    private Set<Jelly> canMoveRecur(Jelly jelly, int dx, int dy, Set<Jelly> moves) {
        Jelly other = jelly;
        while (true) {
            int newx = other.x + dx;
            int newy = other.y + dy;
            for (int i = 0; i < other.shape.getLines().length; i++) {
                int line = other.shape.getLines()[i];
                if ((this.wallLines[newy + i] & (line << newx)) != 0) {
                    return null;
                }
            }
            other = other.linkNext;
            if (other == null || other == jelly) {
                break;
            }
        }

        if (moves == null) {
            moves = new HashSet<>();
        }
        moves.add(jelly);
        if (jelly.linkNext != null) {
            Jelly o = jelly;
            while ((o = o.linkNext) != jelly) {
                moves.add(o);
            }
        }

        Jelly top = jelly;
        while (true) {
            for (Jelly o : this.jellies) {
                if (moves.contains(o)) continue;
                if (o.overlap(jelly, jelly.x + dx, jelly.y + dy)) {
                    if (o.locked) return null;
                    moves = canMoveRecur(o, dx, dy, moves);
                    if (moves == null) return null;
                }
            }
            jelly = jelly.linkNext;
            if (jelly == null || jelly == top) {
                break;
            }
        }
        return moves;
    }

    public FallInfo freeFall(FallInfo fallInfo) {
        int[] wLines;
        List<Jelly> jList;
        if (fallInfo == null) {
            wLines = this.wallLines.clone();
            jList = new ArrayList<>(this.jellies);
            jList.sort((a, b) -> Integer.compare(
                -(a.y + a.shape.getH() - 1),
                -(b.y + b.shape.getH() - 1)
            ));
        } else {
            wLines = fallInfo.wallLines;
            jList = fallInfo.jellies;
        }

        while (true) {
            int i = 0;
            boolean again = false;
            while (i < jList.size()) {
                Jelly jelly = jList.get(i);
                boolean grounded = jelly.locked;
                if (!grounded) {
                    for (int j = 0; j < jelly.shape.getLines().length; j++) {
                        int line = jelly.shape.getLines()[j];
                        if ((wLines[jelly.y + j + 1] & (line << jelly.x)) != 0) {
                            grounded = true;
                            break;
                        }
                    }
                }
                if (grounded) {
                    settleJelly(wLines, jelly);
                    jList.remove(i);
                    if (jelly.linkNext != null) {
                        Jelly linked = jelly;
                        while ((linked = linked.linkNext) != jelly) {
                            int jIdx = indexOfByReference(jList, linked);
                            if (jIdx != -1) {
                                settleJelly(wLines, linked);
                                jList.remove(jIdx);
                            }
                        }
                    }
                    again = true;
                    continue;
                }
                i++;
            }
            if (!again) {
                break;
            }
        }

        if (jList.isEmpty()) {
            return null;
        }

        for (int idx = 0; idx < jList.size(); idx++) {
            Jelly jelly = jList.get(idx);
            if (jelly.isFrozen()) {
                Jelly unfrozen = unfrozenJelly(this.jellies, jelly);

                Jelly src = jelly;
                Jelly dst = unfrozen;
                while (true) {
                    int index = indexOfByReference(jList, src);
                    if (index == -1) {
                        throw new RuntimeException("jelly not found in fall list");
                    }
                    jList.set(index, dst);

                    src = src.linkNext;
                    dst = dst.linkNext;
                    if (src == null || src == jelly) {
                        break;
                    }
                }

                updateHiddensForJelly(jelly, unfrozen);
            }
        }

        for (int idx = 0; idx < jList.size(); idx++) {
            jList.get(idx).y += 1;
        }

        return new FallInfo(wLines, jList);
    }

    public void mergeJellies() {
        int i = 0;
        int j = this.jellies.size() - 1;
        while (true) {
            while (i < j && !this.jellies.get(i).isFrozen()) {
                i++;
            }
            while (i < j && this.jellies.get(j).isFrozen()) {
                j--;
            }
            if (i >= j) {
                break;
            }
            Jelly temp = this.jellies.get(i);
            this.jellies.set(i, this.jellies.get(j));
            this.jellies.set(j, temp);
            i++;
            j--;
        }

        for (int idx = 0; idx < this.jellies.size(); idx++) {
            Jelly jelly = this.jellies.get(idx);
            if (jelly == null || jelly.color == Const.BLACK) {
                continue;
            }

            int otherIdx = idx + 1;
            while (otherIdx < this.jellies.size()) {
                Jelly other = this.jellies.get(otherIdx);
                if (other == null || other.color != jelly.color) {
                    otherIdx++;
                    continue;
                }
                if (jelly.adjacent(other)) {
                    if (jelly.isFrozen()) {
                        throw new RuntimeException("Invalid: target jelly is frozen");
                    }
                    jelly.merge(other);
                    this.jellies.set(otherIdx, null);
                    linkMergedJelly(jelly, other);
                    otherIdx = idx;
                }
                otherIdx++;
            }
        }

        this.jellies.removeIf(Objects::isNull);
    }

    private void linkMergedJelly(Jelly jelly, Jelly other) {
        if (other.linkNext != null) {
            if (jelly.linkNext != null && jelly.containsLink(other)) {
                other.linkPrev.linkNext = other.linkNext;
                other.linkNext.linkPrev = other.linkPrev;
            } else {
                Jelly nxt = other;
                Jelly prv = null;
                while (true) {
                    nxt = nxt.linkNext;
                    if (nxt == other) {
                        break;
                    }
                    Jelly cloned = nxt.shallowCopy();
                    cloned.linkNext = cloned;
                    cloned.linkPrev = cloned;
                    if (prv != null) {
                        prv.link(cloned);
                    }
                    prv = cloned;
                }
                Jelly nxtLink = prv.linkNext;
                jelly.link(nxtLink);

                Jelly q = other;
                Jelly r = nxtLink;
                while ((q = q.linkNext) != other) {
                    int k = indexOfByReference(this.jellies, q);
                    if (k == -1) {
                        throw new RuntimeException("jelly not found in link update");
                    }
                    this.jellies.set(k, r);
                    r = r.linkNext;
                }
            }
        }

        if (jelly.locked) {
            Jelly q = jelly;
            while (true) {
                q.locked = true;
                q = q.linkNext;
                if (q == null || q == jelly) {
                    break;
                }
            }
        }
    }

    public Stage applyHiddens() {
        if (this.hiddens == null) return null;

        Stage applied = null;
        int i = 0;
        while (i < this.hiddens.size()) {
            Hidden hidden = this.hiddens.get(i);
            int hx = hidden.x;
            int hy = hidden.y;
            if (hidden.jelly != null) {
                hx += hidden.jelly.x;
                hy += hidden.jelly.y;
            }

            boolean hiddenRemoved = false;
            for (int j = 0; j < this.jellies.size(); j++) {
                Jelly jelly = this.jellies.get(j);
                if (jelly.color == hidden.color && jelly.occupyPosition(hx + hidden.dx, hy + hidden.dy)) {
                    if (applyHidden(j, hidden)) {
                        this.hiddens = new ArrayList<>(this.hiddens);
                        this.hiddens.remove(i);
                        i--;
                        applied = this;
                        hiddenRemoved = true;
                        break;
                    }
                }
            }
            i++;
        }
        if (this.hiddens != null && this.hiddens.isEmpty()) {
            this.hiddens = null;
        }
        return applied;
    }

    private boolean applyHidden(int j, Hidden hidden) {
        Jelly jelly = this.jellies.get(j);
        int ox = jelly.x;
        int oy = jelly.y;

        int hx = hidden.x;
        int hy = hidden.y;
        Jelly owner = hidden.jelly;
        if (owner != null) {
            hx += owner.x;
            hy += owner.y;
        }

        Stage updated = canMove(jelly, hidden.dx, hidden.dy);
        boolean ownerMoved = false;

        if (updated == null) {
            if (owner == null) {
                return false;
            }
            updated = canMove(owner, -hidden.dx, -hidden.dy);
            if (updated == null) {
                return false;
            }
            if (updated != this) {
                throw new RuntimeException("Unexpected: updated stage is not this");
            }
            if (owner.isFrozen()) {
                final Jelly oldOwner = owner;
                owner = this.jellies.stream()
                    .filter(other -> other.x == oldOwner.x - hidden.dx &&
                                     other.y == oldOwner.y - hidden.dy &&
                                     other.color == oldOwner.color &&
                                     Objects.equals(other.shape, oldOwner.shape))
                    .findFirst()
                    .orElse(null);
                if (owner == null) {
                    throw new RuntimeException("owner not found");
                }
            }
            hx -= hidden.dx;
            hy -= hidden.dy;
            ownerMoved = true;

            if (jelly.isFrozen()) {
                jelly = unfrozenJelly(this.jellies, jelly);
            }
        } else {
            int targetX = ox + hidden.dx;
            int targetY = oy + hidden.dy;
            final Jelly targetJelly = jelly;
            int k = -1;
            for (int idx = 0; idx < this.jellies.size(); idx++) {
                Jelly other = this.jellies.get(idx);
                if (other.x == targetX && other.y == targetY && other.color == targetJelly.color && Objects.equals(other.shape, targetJelly.shape)) {
                    k = idx;
                    break;
                }
            }
            if (k != j) {
                j = k;
                jelly = this.jellies.get(j);
            }
        }

        if (updated != this) {
            throw new RuntimeException("Unexpected: updated stage is not this");
        }

        boolean appearedLocked = hidden.link && owner == null;
        List<Point> singlePos = List.of(new Point(0, 0));
        Jelly appeared = new Jelly(hx + hidden.dx, hy + hidden.dy, hidden.color, JellyShape.registerShape(singlePos), appearedLocked);
        this.jellies.get(j).merge(appeared);

        if (owner != null && !ownerMoved) {
            if (owner.isFrozen()) {
                if (this.frozen) {
                    throw new RuntimeException("Stage is frozen");
                }
                owner = unfrozenJelly(this.jellies, owner);
            }
            owner.removeHidden(hx - owner.x, hy - owner.y);
            if (hidden.link) {
                owner.link(this.jellies.get(j));
            }
        }
        return true;
    }

    public int estimateDistance() {
        Map<Character, List<Jelly>> colorJellies = new HashMap<>();
        for (Jelly jelly : this.jellies) {
            if (jelly.color == Const.BLACK) continue;
            colorJellies.computeIfAbsent(jelly.color, k -> new ArrayList<>()).add(jelly);
        }

        int dist = 0;
        for (List<Jelly> list : colorJellies.values()) {
            if (list.size() < 2) continue;
            Jelly jl = list.stream().min(Comparator.comparingInt(a -> a.x)).orElse(null);
            Jelly jr = list.stream().max(Comparator.comparingInt(a -> a.x + a.shape.getW())).orElse(null);
            if (jl != null && jr != null) {
                dist += Math.max(jr.x - (jl.x + jl.shape.getW()), 1);
            }
        }

        if (this.hiddens != null) {
            int d = 0;
            for (Hidden hidden : this.hiddens) {
                int hx = hidden.x;
                int hy = hidden.y;
                if (hidden.jelly != null) {
                    hx += hidden.jelly.x;
                    hy += hidden.jelly.y;
                }

                List<Jelly> list = colorJellies.get(hidden.color);
                if (list == null || list.isEmpty()) continue;
                Jelly jl = list.stream().min(Comparator.comparingInt(a -> a.x)).orElse(null);
                Jelly jr = list.stream().max(Comparator.comparingInt(a -> a.x + a.shape.getW())).orElse(null);

                if (jl != null && jr != null) {
                    if (hx < jl.x) {
                        d += (jl.x - hx);
                    } else if (hx >= jr.x + jr.shape.getW()) {
                        d += (hx - (jr.x + jr.shape.getW()));
                    } else {
                        d += 1;
                    }
                }
            }
            dist += d;
        }
        return dist;
    }

    public List<String> makeLines() {
        int width = getWidth();
        int height = getHeight();
        char[][] grid = new char[height][width];

        for (int y = 0; y < height; y++) {
            int line = this.wallLines[y];
            for (int x = 0; x < width; x++) {
                if ((line & (1 << x)) != 0) {
                    grid[y][x] = Const.WALL_CHAR;
                } else {
                    grid[y][x] = Const.EMPTY_CHAR;
                }
            }
        }

        for (Jelly jelly : this.jellies) {
            char c = jelly.color;
            if (c == Const.BLACK) {
                if (jelly.blackChar != null) {
                    c = jelly.blackChar;
                }
            } else {
                if (jelly.locked) {
                    c = Character.toLowerCase(c);
                }
            }
            for (Point p : jelly.shape.getPositions()) {
                grid[p.y() + jelly.y][p.x() + jelly.x] = c;
            }
        }

        List<String> result = new ArrayList<>();
        for (int y = 0; y < height; y++) {
            result.add(new String(grid[y]));
        }
        return result;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        Stage stage = (Stage) o;

        if (!Arrays.equals(wallLines, stage.wallLines)) return false;

        List<Jelly> thisSorted = this.sortedJelliesCache != null ? this.sortedJelliesCache : this.jellies;
        List<Jelly> otherSorted = stage.sortedJelliesCache != null ? stage.sortedJelliesCache : stage.jellies;

        if (this.sortedJelliesCache == null || stage.sortedJelliesCache == null) {
            thisSorted = new ArrayList<>(thisSorted);
            Collections.sort(thisSorted);
            otherSorted = new ArrayList<>(otherSorted);
            Collections.sort(otherSorted);
        }

        if (!thisSorted.equals(otherSorted)) return false;

        if (this.hiddens == null && stage.hiddens == null) return true;
        if (this.hiddens == null || stage.hiddens == null) return false;
        if (this.hiddens.size() != stage.hiddens.size()) return false;

        List<Hidden> thisH = this.sortedHiddensCache;
        List<Hidden> otherH = stage.sortedHiddensCache;
        if (thisH == null || otherH == null) {
            thisH = new ArrayList<>(this.hiddens);
            otherH = new ArrayList<>(stage.hiddens);
            Comparator<Hidden> hc = (a, b) -> {
                if (a.x != b.x) return Integer.compare(a.x, b.x);
                if (a.y != b.y) return Integer.compare(a.y, b.y);
                if (a.color != b.color) return Character.compare(a.color, b.color);
                if (a.dx != b.dx) return Integer.compare(a.dx, b.dx);
                if (a.dy != b.dy) return Integer.compare(a.dy, b.dy);
                return Boolean.compare(a.link, b.link);
            };
            thisH.sort(hc);
            otherH.sort(hc);
        }

        return thisH.equals(otherH);
    }

    @Override
    public int hashCode() {
        List<Jelly> thisSorted = this.sortedJelliesCache;
        if (thisSorted == null) {
            thisSorted = new ArrayList<>(this.jellies);
            Collections.sort(thisSorted);
        }
        int jHash = thisSorted.hashCode();

        int hHash = 0;
        if (this.hiddens != null) {
            List<Hidden> thisH = this.sortedHiddensCache;
            if (thisH == null) {
                thisH = new ArrayList<>(this.hiddens);
                thisH.sort((a, b) -> {
                    if (a.x != b.x) return Integer.compare(a.x, b.x);
                    if (a.y != b.y) return Integer.compare(a.y, b.y);
                    if (a.color != b.color) return Character.compare(a.color, b.color);
                    if (a.dx != b.dx) return Integer.compare(a.dx, b.dx);
                    if (a.dy != b.dy) return Integer.compare(a.dy, b.dy);
                    return Boolean.compare(a.link, b.link);
                });
            }
            hHash = thisH.hashCode();
        }

        return Objects.hash(jHash, hHash);
    }
}
