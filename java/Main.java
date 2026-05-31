import jelly.*;

import java.io.BufferedReader;
import java.io.FileReader;
import java.io.IOException;
import java.util.List;
import java.util.Objects;

public class Main {
    private static void dispStage(Stage stage) {
        List<String> lines = stage.makeLines();
        for (String line : lines) {
            System.out.println(line);
        }
    }

    private static void dispSolution(Stage stage, List<Move> moves) {
        dispStage(stage);
        for (Move move : moves) {
            System.out.println(move.toString());
            Jelly jelly = null;
            for (Jelly j : stage.jellies) {
                if (j.occupyPosition(move.x(), move.y())) {
                    jelly = j;
                    break;
                }
            }
            if (jelly == null) {
                throw new RuntimeException("Jelly not found for move: " + move);
            }
            stage = Solver.moveJelly(stage, jelly, move.dx());
            if (stage == null) {
                throw new RuntimeException("Invalid move: " + move);
            }
            dispStage(stage);
        }
    }

    public static void main(String[] args) {
        boolean noPrune = false;
        boolean useBfs = false;
        boolean quiet = false;
        boolean parallel = false;
        String filename = null;

        for (String arg : args) {
            if (arg.equals("--no-prune")) {
                noPrune = true;
            } else if (arg.equals("--bfs")) {
                useBfs = true;
            } else if (arg.equals("--quiet")) {
                quiet = true;
            } else if (arg.equals("--parallel")) {
                parallel = true;
            } else if (arg.startsWith("-")) {
                System.err.println("Unknown option: " + arg);
                System.exit(1);
            } else {
                filename = arg;
            }
        }

        if (filename == null) {
            System.err.println("Usage: java Main [--no-prune] [--bfs] [--quiet] [--parallel] <stage_file>");
            System.exit(1);
        }

        Stage stage = null;
        try (BufferedReader br = new BufferedReader(new FileReader(filename))) {
            StageParser parser = new StageParser();
            stage = parser.parse(br);
        } catch (IOException e) {
            System.err.println("Failed to read file: " + filename);
            e.printStackTrace();
            System.exit(1);
        }

        Solver solver = new Solver(noPrune, useBfs, quiet, parallel);
        long startTime = System.nanoTime();
        List<Move> moves = solver.solve(stage.dup());
        long endTime = System.nanoTime();
        double elapsed = (endTime - startTime) / 1_000_000_000.0;

        if (moves != null) {
            if (!quiet) {
                dispSolution(stage, moves);
            }
            System.out.printf("Steps=%d, check=%d, elapsed=%.3fs\n", moves.size(), solver.getCheckCount(), elapsed);
        } else {
            System.out.printf("No solution found. check=%d, elapsed=%.3fs\n", solver.getCheckCount(), elapsed);
        }
    }
}
