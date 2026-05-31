use std::collections::{HashMap, VecDeque};
use std::io::{BufRead, BufReader, Read};
use std::sync::Arc;
use crate::point::Point;
use crate::jelly_shape::JellyShape;
use crate::jelly::{Jelly, Hidden};
use crate::stage::Stage;
use crate::consts::{WALL, VACANT, BLACK};

pub struct StageParser;

struct ExtraData {
    links: Vec<Vec<usize>>,
    hiddens: Vec<Hidden>,
}

impl StageParser {
    pub fn parse<R: Read>(&self, reader: R) -> Result<Stage, String> {
        let mut buf_reader = BufReader::new(reader);
        let mut stage_array: Vec<Vec<char>> = Vec::new();

        loop {
            let mut line = String::new();
            let size = buf_reader.read_line(&mut line).map_err(|e| e.to_string())?;
            if size == 0 {
                break;
            }
            let trimmed = line.trim_end_matches('\n').trim_end_matches('\r');
            if trimmed.is_empty() {
                break;
            }
            stage_array.push(trimmed.chars().collect());
        }

        if stage_array.is_empty() {
            return Err("Empty stage data".to_string());
        }

        let width = stage_array[0].len() + 2;

        let mut wall_lines = Vec::new();
        // 最初の行は全面壁
        wall_lines.push((1 << width) - 1);

        let mut jellies = Vec::new();
        let shape1 = JellyShape::register_shape(vec![Point::new(0, 0)]);

        let mut jelly_id_gen = 0;

        for y in 0..stage_array.len() {
            let mut line_bits = 1 | (1 << (width - 1));

            let mut x = 0;
            while x < stage_array[y].len() {
                let cell = stage_array[y][x];
                let c = cell.to_ascii_uppercase();

                if c.is_ascii_alphabetic() {
                    let locked = c != cell;
                    let jelly = Jelly::new(jelly_id_gen, x as i32 + 1, y as i32 + 1, c, shape1.clone(), locked);
                    jelly_id_gen += 1;
                    jellies.push(jelly);
                } else {
                    match cell {
                        WALL => {
                            line_bits |= 1 << (x + 1);
                        }
                        '@' | '*' | '$' | '%' => {
                            let mut black_block = Self::parse_black_block(&mut stage_array, x, y);
                            black_block.id = jelly_id_gen;
                            black_block.parent_id = jelly_id_gen;
                            jelly_id_gen += 1;
                            jellies.push(black_block);
                        }
                        VACANT => {
                            // 空きマス（ゴールなどの概念はなく、'G' は緑色のゼリー）
                        }
                        _ => {
                            return Err(format!("Unknown cell: '{}' at ({}, {})", cell, x, y));
                        }
                    }
                }
                x += 1;
            }
            wall_lines.push(line_bits);
        }

        // 最後の行も全面壁
        wall_lines.push((1 << width) - 1);

        // 追加コマンド（link, hidden）のパース
        let extra = Self::parse_extra(&mut buf_reader, width as i32, (stage_array.len() + 2) as i32, &mut jellies)?;

        let jellies: Vec<Arc<Jelly>> = jellies.into_iter().map(Arc::new).collect();
        let mut stage = Stage::new(wall_lines, jellies, if extra.hiddens.is_empty() { None } else { Some(extra.hiddens) });

        // linkの結合処理
        for link in &extra.links {
            if link.is_empty() {
                continue;
            }
            let root1 = stage.find_group(link[0]);
            for i in 1..link.len() {
                let root2 = stage.find_group(link[i]);
                stage.link_group(root1, root2);
            }
        }

        stage.merge_jellies();
        Ok(stage)
    }

    fn parse_extra<R: BufRead>(reader: &mut R, width: i32, height: i32, jellies: &mut Vec<Jelly>) -> Result<ExtraData, String> {
        let mut extra = ExtraData {
            links: Vec::new(),
            hiddens: Vec::new(),
        };

        let dirs: HashMap<char, (i32, i32)> = [
            ('<', (-1, 0)),
            ('>', (1, 0)),
            ('^', (0, -1)),
            ('v', (0, 1)),
        ].into_iter().collect();

        let mut line = String::new();
        while reader.read_line(&mut line).map_err(|e| e.to_string())? > 0 {
            let trimmed = line.trim();
            if trimmed.is_empty() || trimmed.starts_with("//") {
                line.clear();
                continue;
            }

            // link X,Y,DIR のパース
            if trimmed.starts_with("link") {
                let parts: Vec<&str> = trimmed.split_whitespace().collect();
                if parts.len() == 2 {
                    let subparts: Vec<&str> = parts[1].split(',').collect();
                    if subparts.len() == 3 {
                        let x: i32 = subparts[0].parse().map_err(|_| "Invalid int")?;
                        let y: i32 = subparts[1].parse().map_err(|_| "Invalid int")?;
                        let dir_char = subparts[2].chars().next().unwrap();

                        if x >= 1 && x < width - 1 && y >= 1 && y < height - 1 {
                            if let Some(d) = dirs.get(&dir_char) {
                                let jelly_id = Self::find_jelly_occupying(jellies, x, y);
                                let dest_id = Self::find_jelly_occupying(jellies, x + d.0, y + d.1);
                                if let (Some(j_id), Some(d_id)) = (jelly_id, dest_id) {
                                    let mut done = false;
                                    for link in &mut extra.links {
                                        if link.contains(&j_id) {
                                            link.push(d_id);
                                            done = true;
                                            break;
                                        } else if link.contains(&d_id) {
                                            link.push(j_id);
                                            done = true;
                                            break;
                                        }
                                    }
                                    if !done {
                                        extra.links.push(vec![j_id, d_id]);
                                    }
                                }
                            }
                        }
                    }
                }
                line.clear();
                continue;
            }

            // hidden 又は hidden+link のパース
            if trimmed.starts_with("hidden") {
                let has_link = trimmed.starts_with("hidden+link");
                let parts: Vec<&str> = trimmed.split_whitespace().collect();
                if parts.len() == 2 {
                    let subparts: Vec<&str> = parts[1].split(',').collect();
                    if subparts.len() == 4 {
                        let x: i32 = subparts[0].parse().map_err(|_| "Invalid int")?;
                        let y: i32 = subparts[1].parse().map_err(|_| "Invalid int")?;
                        let color = subparts[2].chars().next().unwrap();
                        let dir_char = subparts[3].chars().next().unwrap();

                        if let Some(d) = dirs.get(&dir_char) {
                            let mut hidden = Hidden::new(x, y, color, d.0, d.1, None, has_link);
                            let jelly_idx = jellies.iter().position(|j| j.occupy_position(x, y));
                            if let Some(j_idx) = jelly_idx {
                                let j_id = jellies[j_idx].id;
                                hidden.x -= jellies[j_idx].x;
                                hidden.y -= jellies[j_idx].y;
                                hidden.jelly_id = Some(j_id);
                                jellies[j_idx].add_hidden(hidden);
                            }
                            extra.hiddens.push(hidden);
                        }
                    }
                }
                line.clear();
                continue;
            }

            return Err(format!("Invalid format: {}", trimmed));
        }

        Ok(extra)
    }

    fn find_jelly_occupying(jellies: &[Jelly], x: i32, y: i32) -> Option<usize> {
        jellies.iter().find(|j| j.occupy_position(x, y)).map(|j| j.id)
    }

    fn parse_black_block(stage_array: &mut [Vec<char>], start_x: usize, start_y: usize) -> Jelly {
        let h = stage_array.len();
        let w = stage_array[0].len();
        let c = stage_array[start_y][start_x];

        let mut unchecked = VecDeque::new();
        unchecked.push_back(Point::new(start_x as i32, start_y as i32));
        let mut positions = Vec::new();
        let mut min_x = start_x as i32;
        let mut min_y = start_y as i32;

        let dirs = [(-1, 0), (1, 0), (0, -1), (0, 1)];
        while let Some(p) = unchecked.pop_front() {
            if stage_array[p.y as usize][p.x as usize] != c {
                continue;
            }
            stage_array[p.y as usize][p.x as usize] = VACANT;
            positions.push(p);
            min_x = std::cmp::min(min_x, p.x);
            min_y = std::cmp::min(min_y, p.y);

            for d in &dirs {
                let xx = p.x + d.0;
                let yy = p.y + d.1;
                if xx < 0 || yy < 0 || xx >= w as i32 || yy >= h as i32 {
                    continue;
                }
                unchecked.push_back(Point::new(xx, yy));
            }
        }

        let mut relative_positions = Vec::new();
        for p in &positions {
            relative_positions.push(Point::new(p.x - min_x, p.y - min_y));
        }

        let shape = JellyShape::register_shape(relative_positions);
        let mut black_block = Jelly::new(0, min_x + 1, min_y + 1, BLACK, shape, false);
        black_block.black_char = Some(c);
        black_block
    }
}
