package jelly;

import java.io.BufferedReader;
import java.io.IOException;
import java.util.*;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class StageParser {

    public Stage parse(BufferedReader reader) throws IOException {
        List<char[]> stageArray = new ArrayList<>();
        String line;
        while ((line = reader.readLine()) != null) {
            if (line.equals("\n") || line.isEmpty()) {
                break;
            }
            stageArray.add(line.toCharArray());
        }

        if (stageArray.isEmpty()) {
            throw new RuntimeException("Empty stage data");
        }

        int width = stageArray.get(0).length + 2;
        int height = stageArray.size() + 2;

        List<Integer> wallLinesList = new ArrayList<>();
        // 最初の行は全面壁
        wallLinesList.add((1 << width) - 1);

        List<Jelly> jellies = new ArrayList<>();
        JellyShape shape1 = JellyShape.registerShape(List.of(new Point(0, 0)));

        Pattern jellyPattern = Pattern.compile(Const.RE_JELLY_CHARS);

        for (int y = 0; y < stageArray.size(); y++) {
            char[] row = stageArray.get(y);
            // 左右の端を壁にする
            int lineBits = 1 | (1 << (width - 1));

            for (int x = 0; x < row.length; x++) {
                char cell = row[x];
                char c = Character.toUpperCase(cell);

                if (jellyPattern.matcher(String.valueOf(c)).matches()) {
                    boolean locked = c != cell;
                    // 壁考慮のため座標は+1
                    Jelly singleJelly = new Jelly(x + 1, y + 1, c, shape1, locked);
                    jellies.add(singleJelly);
                    continue;
                }

                switch (cell) {
                    case Const.WALL_CHAR:
                        lineBits |= 1 << (x + 1);
                        break;
                    case '@':
                    case '*':
                    case '$':
                    case '%':
                        Jelly blackBlock = parseBlackBlock(stageArray, x, y);
                        jellies.add(blackBlock);
                        break;
                    case Const.EMPTY_CHAR:
                        // 空きマス
                        break;
                    default:
                        System.err.println("Unknown cell: '" + cell + "' at (" + x + ", " + y + ")");
                        System.exit(1);
                }
            }
            wallLinesList.add(lineBits);
        }

        // 最後の行も全面壁
        wallLinesList.add((1 << width) - 1);

        int[] wallLines = wallLinesList.stream().mapToInt(Integer::intValue).toArray();

        // 追加コマンド（link, hidden）のパース
        ExtraData extra = parseExtra(reader, width, height, jellies);

        // linkの結合処理
        for (List<Jelly> link : extra.links) {
            if (link.isEmpty()) continue;
            Jelly top = link.get(0);
            for (int i = 1; i < link.size(); i++) {
                Jelly nextJelly = link.get(i);
                top.link(nextJelly);
                top = nextJelly;
            }
        }

        List<Hidden> hiddenList = extra.hiddens.isEmpty() ? null : extra.hiddens;
        Stage stage = new Stage(wallLines, jellies, hiddenList);
        stage.mergeJellies();
        return stage;
    }

    private static class ExtraData {
        public List<List<Jelly>> links = new ArrayList<>();
        public List<Hidden> hiddens = new ArrayList<>();
    }

    private ExtraData parseExtra(BufferedReader reader, int width, int height, List<Jelly> jellies) throws IOException {
        ExtraData extra = new ExtraData();
        String line;
        Pattern commentPattern = Pattern.compile("^//");
        Pattern linkPattern = Pattern.compile("^link\\s+(\\d+),(\\d+),([<>^v])$");
        Pattern hiddenPattern = Pattern.compile("^hidden(\\+link)?\\s+(\\d+),(\\d+),(" + Const.RE_JELLY_CHARS + "),([<>^v])$");

        while ((line = reader.readLine()) != null) {
            line = line.trim();
            if (line.isEmpty()) {
                continue;
            }
            if (commentPattern.matcher(line).find()) {
                continue;
            }

            Matcher linkMatcher = linkPattern.matcher(line);
            if (linkMatcher.matches()) {
                int x = Integer.parseInt(linkMatcher.group(1));
                int y = Integer.parseInt(linkMatcher.group(2));
                char dirChar = linkMatcher.group(3).charAt(0);

                if ((x >= 1 && x < width - 1) || y >= 1 || y < height - 1 || Const.DIRS.containsKey(dirChar)) {
                    int[] d = Const.DIRS.get(dirChar);
                    Jelly jelly = findJellyOccupying(jellies, x, y);
                    Jelly dest = findJellyOccupying(jellies, x + d[0], y + d[1]);
                    if (jelly != null && dest != null) {
                        boolean done = false;
                        for (List<Jelly> link : extra.links) {
                            if (link.contains(jelly)) {
                                link.add(dest);
                                done = true;
                                break;
                            } else if (link.contains(dest)) {
                                link.add(jelly);
                                done = true;
                                break;
                            }
                        }
                        if (!done) {
                            List<Jelly> newLink = new ArrayList<>();
                            newLink.add(jelly);
                            newLink.add(dest);
                            extra.links.add(newLink);
                        }
                    }
                }
                continue;
            }

            Matcher hiddenMatcher = hiddenPattern.matcher(line);
            if (hiddenMatcher.matches()) {
                boolean hasLink = hiddenMatcher.group(1) != null;
                int x = Integer.parseInt(hiddenMatcher.group(2));
                int y = Integer.parseInt(hiddenMatcher.group(3));
                char color = hiddenMatcher.group(4).charAt(0);
                char dirChar = hiddenMatcher.group(5).charAt(0);

                int[] d = Const.DIRS.get(dirChar);
                Hidden hidden = new Hidden(x, y, color, d[0], d[1], null, hasLink);
                Jelly jelly = findJellyOccupying(jellies, x, y);
                if (jelly != null) {
                    hidden.x -= jelly.x;
                    hidden.y -= jelly.y;
                    hidden.jelly = jelly;
                    jelly.addHidden(hidden);
                }
                extra.hiddens.add(hidden);
                continue;
            }

            throw new RuntimeException("Invalid format: " + line);
        }
        return extra;
    }

    private Jelly findJellyOccupying(List<Jelly> jellies, int x, int y) {
        for (Jelly j : jellies) {
            if (j.occupyPosition(x, y)) {
                return j;
            }
        }
        return null;
    }

    private Jelly parseBlackBlock(List<char[]> stageArray, int startX, int startY) {
        int h = stageArray.size();
        int w = stageArray.get(0).length;
        char c = stageArray.get(startY)[startX];

        Queue<Point> unchecked = new LinkedList<>();
        unchecked.add(new Point(startX, startY));
        List<Point> positions = new ArrayList<>();
        int minX = startX;
        int minY = startY;

        int[][] dirs = {{-1, 0}, {1, 0}, {0, -1}, {0, 1}};
        while (!unchecked.isEmpty()) {
            Point p = unchecked.poll();
            if (stageArray.get(p.y())[p.x()] != c) {
                continue;
            }
            stageArray.get(p.y())[p.x()] = Const.EMPTY_CHAR;
            positions.add(p);
            minX = Math.min(minX, p.x());
            minY = Math.min(minY, p.y());

            for (int[] d : dirs) {
                int xx = p.x() + d[0];
                int yy = p.y() + d[1];
                if (xx < 0 || yy < 0 || xx >= w || yy >= h) {
                    continue;
                }
                unchecked.add(new Point(xx, yy));
            }
        }

        List<Point> relativePositions = new ArrayList<>();
        for (Point p : positions) {
            relativePositions.add(new Point(p.x() - minX, p.y() - minY));
        }

        JellyShape shape = JellyShape.registerShape(relativePositions);
        Jelly blackBlock = new Jelly(minX + 1, minY + 1, Const.BLACK, shape, false);
        blackBlock.blackChar = c;
        return blackBlock;
    }
}
