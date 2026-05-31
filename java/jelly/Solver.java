package jelly;

import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;

public class Solver {
    private final boolean noPrune;
    private final boolean useBfs;
    private final boolean quiet;
    private final boolean parallel;
    private int checkCount;
    private Map<Character, Integer> constraints;
    private int maxy;

    public Solver(boolean noPrune, boolean useBfs, boolean quiet, boolean parallel) {
        this.noPrune = noPrune;
        this.useBfs = useBfs;
        this.quiet = quiet;
        this.parallel = parallel;
        this.checkCount = 0;
    }

    public int getCheckCount() {
        return checkCount;
    }

    private static class SearchNode {
        final Stage stage;
        final int step;
        final int fScore;

        SearchNode(Stage stage, int step, boolean useBfs) {
            this.stage = stage;
            this.step = step;
            this.fScore = useBfs ? 0 : stage.distance + step;
        }
    }

    private static class NodeHistory {
        final Stage prevStage;
        final Move move;
        NodeHistory(Stage prevStage, Move move) {
            this.prevStage = prevStage;
            this.move = move;
        }
    }

    public List<Move> solve(Stage stage) {
        if (parallel) {
            return solveParallel(stage);
        } else {
            return solveSequential(stage);
        }
    }

    private List<Move> solveSequential(Stage stage) {
        if (!noPrune) {
            detectConstraint(stage);
        }

        if (!useBfs) {
            stage.distance = stage.estimateDistance();
        }
        stage.freeze();

        Queue<SearchNode> que;
        if (useBfs) {
            que = new LinkedList<>();
        } else {
            que = new PriorityQueue<>(Comparator.comparingInt(a -> a.fScore));
        }

        que.add(new SearchNode(stage, 0, useBfs));

        Map<Stage, NodeHistory> nodes = new HashMap<>();
        nodes.put(stage, new NodeHistory(null, null));

        int checkCount = 0;

        while (!que.isEmpty()) {
            SearchNode node = que.poll();
            Stage currentStage = node.stage;
            int step = node.step;
            checkCount++;

            if (!quiet) {
                System.err.print("\rCheck=" + checkCount + ", left=" + que.size() + "\033[0K");
                System.err.flush();
            }

            if (!noPrune && unsolvable(currentStage)) {
                continue;
            }

            if (currentStage.solved()) {
                this.checkCount = checkCount;
                if (!quiet) {
                    System.err.print("\rSolved!\033[0K\n");
                    System.err.flush();
                }
                return extractMoves(nodes, currentStage);
            }

            final int nextStep = step + 1;
            enumerateNext(currentStage, (nextStage, move) -> {
                nextStage.freeze();
                if (!nodes.containsKey(nextStage)) {
                    nodes.put(nextStage, new NodeHistory(currentStage, move));
                    if (!useBfs) {
                        nextStage.distance = nextStage.estimateDistance();
                    }
                    que.add(new SearchNode(nextStage, nextStep, useBfs));
                }
            });
        }

        this.checkCount = checkCount;
        return null;
    }

    private List<Move> solveParallel(Stage stage) {
        if (!noPrune) {
            detectConstraint(stage);
        }

        if (!useBfs) {
            stage.distance = stage.estimateDistance();
        }
        stage.freeze();

        BlockingQueue<SearchNode> que;
        if (useBfs) {
            que = new LinkedBlockingQueue<>();
        } else {
            que = new PriorityBlockingQueue<>(11, Comparator.comparingInt(a -> a.fScore));
        }

        ConcurrentMap<Stage, NodeHistory> nodes = new ConcurrentHashMap<>();
        nodes.put(stage, new NodeHistory(null, null));

        que.add(new SearchNode(stage, 0, useBfs));

        int numThreads = Runtime.getRuntime().availableProcessors();
        ExecutorService executor = Executors.newFixedThreadPool(numThreads);

        AtomicInteger activeWorkers = new AtomicInteger(0);
        AtomicInteger globalCheckCount = new AtomicInteger(0);
        AtomicReference<Stage> goalStage = new AtomicReference<>(null);

        Object lock = new Object();

        class Worker implements Runnable {
            @Override
            public void run() {
                while (goalStage.get() == null) {
                    SearchNode node = null;
                    try {
                        node = que.poll(10, TimeUnit.MILLISECONDS);
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                        break;
                    }

                    if (node == null) {
                        if (activeWorkers.get() == 0 && que.isEmpty()) {
                            synchronized (lock) {
                                lock.notifyAll();
                            }
                            break;
                        }
                        continue;
                    }

                    activeWorkers.incrementAndGet();
                    try {
                        Stage currentStage = node.stage;
                        int step = node.step;
                        int currentCheck = globalCheckCount.incrementAndGet();

                        if (!quiet && currentCheck % 1000 == 0) {
                            System.err.print("\rCheck=" + currentCheck + ", left=" + que.size() + "\033[0K");
                            System.err.flush();
                        }

                        if (!noPrune && unsolvable(currentStage)) {
                            continue;
                        }

                        if (currentStage.solved()) {
                            goalStage.compareAndSet(null, currentStage);
                            synchronized (lock) {
                                lock.notifyAll();
                            }
                            break;
                        }

                        final int nextStep = step + 1;
                        enumerateNext(currentStage, (nextStage, move) -> {
                            nextStage.freeze();
                            if (nodes.putIfAbsent(nextStage, new NodeHistory(currentStage, move)) == null) {
                                if (!useBfs) {
                                    nextStage.distance = nextStage.estimateDistance();
                                }
                                que.add(new SearchNode(nextStage, nextStep, useBfs));
                            }
                        });
                    } finally {
                        activeWorkers.decrementAndGet();
                    }
                }

                synchronized (lock) {
                    lock.notifyAll();
                }
            }
        }

        for (int i = 0; i < numThreads; i++) {
            executor.submit(new Worker());
        }

        synchronized (lock) {
            while (goalStage.get() == null && (activeWorkers.get() > 0 || !que.isEmpty())) {
                try {
                    lock.wait(100);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    break;
                }
            }
        }

        executor.shutdownNow();
        try {
            executor.awaitTermination(1, TimeUnit.SECONDS);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }

        this.checkCount = globalCheckCount.get();
        Stage finalGoal = goalStage.get();
        if (finalGoal != null) {
            if (!quiet) {
                System.err.print("\rSolved!\033[0K\n");
                System.err.flush();
            }
            return extractMoves(nodes, finalGoal);
        }

        return null;
    }

    private List<Move> extractMoves(Map<Stage, NodeHistory> nodes, Stage goalStage) {
        List<Move> moves = new ArrayList<>();
        Stage curr = goalStage;
        while (true) {
            NodeHistory history = nodes.get(curr);
            if (history == null || history.prevStage == null) {
                break;
            }
            moves.add(history.move);
            curr = history.prevStage;
        }
        Collections.reverse(moves);
        return moves;
    }

    public interface NextStageCallback {
        void onNextStage(Stage nextStage, Move move);
    }

    public void enumerateNext(Stage stage, NextStageCallback callback) {
        Set<Jelly> skips = new HashSet<>();
        for (Jelly jelly : stage.jellies) {
            if (skips.contains(jelly)) {
                continue;
            }
            for (int j = 0; j < 2; j++) {
                int dx = j * 2 - 1;
                Stage updated = moveJelly(stage, jelly, dx);
                if (updated != null) {
                    Point top = jelly.shape.getPositions().get(0);
                    Move move = new Move(jelly.x + top.x(), jelly.y + top.y(), dx);
                    callback.onNextStage(updated, move);
                }
            }

            if (jelly.linkNext != null) {
                Jelly other = jelly;
                while (true) {
                    skips.add(other);
                    other = other.linkNext;
                    if (other == jelly) {
                        break;
                    }
                }
            }
        }
    }

    public static Stage moveJelly(Stage stage, Jelly jelly, int dx) {
        Stage updated = stage.canMove(jelly, dx, 0);
        if (updated == null) {
            return null;
        }

        while (true) {
            Stage.FallInfo fallInfo = null;
            while (true) {
                Stage.FallInfo nextFall = updated.freeFall(fallInfo);
                if (nextFall == null) {
                    break;
                }
                fallInfo = nextFall;
            }
            updated.mergeJellies();
            if (updated.applyHiddens() == null) {
                break;
            }
        }
        return updated;
    }

    private void detectConstraint(Stage stage) {
        Map<Character, Integer> constraints = new HashMap<>();

        int height = stage.getHeight();
        int width = stage.getWidth();
        int maxy = height - 1;

        while (true) {
            int wallLine = stage.wallLines[maxy];
            if (wallLine != (1 << width) - 1) {
                boolean vacant = false;
                for (int x = 1; x <= width - 2; x++) {
                    if ((wallLine & (1 << x)) != 0) {
                        continue;
                    }
                    final int tx = x;
                    final int ty = maxy;
                    Jelly jelly = stage.jellies.stream()
                        .filter(it -> it.occupyPosition(tx, ty))
                        .findFirst()
                        .orElse(null);
                    if (jelly == null || !jelly.locked) {
                        vacant = true;
                        break;
                    }
                }
                if (vacant) {
                    break;
                }
            }
            maxy--;
        }

        List<Jelly> sortedJellies = new ArrayList<>(stage.jellies);
        Collections.sort(sortedJellies);

        for (Jelly jelly : sortedJellies) {
            if (jelly.y >= maxy) {
                break;
            }
            if (jelly.color == Const.BLACK || !jelly.locked) {
                continue;
            }
            int y = jelly.y + jelly.shape.getH();

            boolean walls = true;
            for (int dx = 0; dx < jelly.shape.getW(); dx++) {
                if ((stage.wallLines[y] & (1 << (jelly.x + dx))) == 0) {
                    walls = false;
                    break;
                }
            }
            if (walls) {
                y -= 1;
            }

            if (!constraints.containsKey(jelly.color) || constraints.get(jelly.color) > y) {
                constraints.put(jelly.color, y);
            }
        }

        if (stage.hiddens != null) {
            for (Hidden hidden : stage.hiddens) {
                if (hidden.jelly == null && hidden.link) {
                    int y = hidden.y + hidden.dy;
                    if (y >= maxy) continue;
                    if (!constraints.containsKey(hidden.color) || constraints.get(hidden.color) > y) {
                        constraints.put(hidden.color, y);
                    }
                }
            }
        }

        this.constraints = constraints.isEmpty() ? null : constraints;
        this.maxy = maxy;
    }

    private boolean unsolvable(Stage stage) {
        Map<Character, Integer> consts = this.constraints;
        int up = 0;
        if (stage.hiddens != null) {
            if (this.constraints != null) {
                consts = new HashMap<>(this.constraints);
            } else {
                consts = new HashMap<>();
            }
            for (Hidden hidden : stage.hiddens) {
                if (hidden.dy <= 0) {
                    up++;
                }
                if (hidden.jelly != null || hidden.link) {
                    continue;
                }
                int y = hidden.y + hidden.dy;
                if (y >= this.maxy) {
                    continue;
                }
                if (!consts.containsKey(hidden.color) || consts.get(hidden.color) > y) {
                    consts.put(hidden.color, y);
                }
            }
        }

        if (consts == null) {
            return false;
        }

        Map<Character, Integer> colorHeights = new HashMap<>();
        for (Jelly jelly : stage.jellies) {
            if (jelly.color == Const.BLACK || jelly.locked || !consts.containsKey(jelly.color)) {
                continue;
            }
            colorHeights.put(jelly.color, colorHeights.getOrDefault(jelly.color, 0) + jelly.shape.getH());
        }

        for (Jelly jelly : stage.jellies) {
            if (jelly.color == Const.BLACK || jelly.locked || !consts.containsKey(jelly.color)) {
                continue;
            }
            int h = colorHeights.getOrDefault(jelly.color, 0);
            if (jelly.y - h - up >= consts.get(jelly.color)) {
                return true;
            }
        }
        return false;
    }
}
