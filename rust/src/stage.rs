use std::collections::{HashSet, HashMap};
use std::sync::Arc;
use crate::point::Point;
use crate::jelly_shape::JellyShape;
use crate::jelly::{Jelly, Hidden};
use crate::consts::{WALL, VACANT, BLACK};

#[derive(Clone, Debug)]
pub struct FallInfo {
    pub wall_lines: Vec<i32>,
    pub jellies: Vec<Arc<Jelly>>,
}

#[derive(Clone, Debug, Eq)]
pub struct Stage {
    pub wall_lines: Vec<i32>,
    pub jellies: Vec<Arc<Jelly>>,
    pub hiddens: Option<Vec<Hidden>>,
    pub distance: i32,
    sorted_jellies_cache: Option<Vec<Arc<Jelly>>>,
    sorted_hiddens_cache: Option<Vec<Hidden>>,
    pub hash_code: u64,
}

impl Stage {
    pub fn new(wall_lines: Vec<i32>, jellies: Vec<Arc<Jelly>>, hiddens: Option<Vec<Hidden>>) -> Self {
        Self {
            wall_lines,
            jellies,
            hiddens,
            distance: 0,
            sorted_jellies_cache: None,
            sorted_hiddens_cache: None,
            hash_code: 0,
        }
    }

    pub fn freeze(&mut self) {
        let mut sorted_jellies = self.jellies.clone();
        sorted_jellies.sort();
        self.sorted_jellies_cache = Some(sorted_jellies);

        if let Some(hiddens) = &self.hiddens {
            let mut sorted_hiddens = hiddens.clone();
            sorted_hiddens.sort_by(|a, b| {
                a.x.cmp(&b.x)
                    .then_with(|| a.y.cmp(&b.y))
                    .then_with(|| a.color.cmp(&b.color))
                    .then_with(|| a.dx.cmp(&b.dx))
                    .then_with(|| a.dy.cmp(&b.dy))
                    .then_with(|| a.link.cmp(&b.link))
            });
            self.sorted_hiddens_cache = Some(sorted_hiddens);
        } else {
            self.sorted_hiddens_cache = None;
        }

        self.hash_code = self.calculate_hash();
    }

    fn calculate_hash(&self) -> u64 {
        use std::hash::{Hash, Hasher};
        let mut state = std::collections::hash_map::DefaultHasher::new();
        
        if let Some(cache) = &self.sorted_jellies_cache {
            cache.hash(&mut state);
        } else {
            let mut list = self.jellies.clone();
            list.sort();
            list.hash(&mut state);
        }

        if let Some(hiddens) = &self.hiddens {
            if let Some(cache) = &self.sorted_hiddens_cache {
                cache.hash(&mut state);
            } else {
                let mut list = hiddens.clone();
                list.sort_by(|a, b| {
                    a.x.cmp(&b.x)
                        .then_with(|| a.y.cmp(&b.y))
                        .then_with(|| a.color.cmp(&b.color))
                        .then_with(|| a.dx.cmp(&b.dx))
                        .then_with(|| a.dy.cmp(&b.dy))
                        .then_with(|| a.link.cmp(&b.link))
                });
                list.hash(&mut state);
            }
        }
        state.finish()
    }

    pub fn height(&self) -> usize {
        self.wall_lines.len()
    }

    pub fn width(&self) -> usize {
        if self.wall_lines.is_empty() {
            0
        } else {
            // 最上位ビットの位置から幅を求める
            let mut w = 0;
            let mut line = self.wall_lines[0];
            while line > 0 {
                w += 1;
                line >>= 1;
            }
            w
        }
    }

    pub fn solved(&self) -> bool {
        if self.hiddens.is_some() {
            return false;
        }
        let mut seen_colors = HashSet::new();
        for jelly in &self.jellies {
            if jelly.color == BLACK {
                continue;
            }
            if seen_colors.contains(&jelly.color) {
                return false;
            }
            seen_colors.insert(jelly.color);
        }
        true
    }

    pub fn find_jelly_by_id(&self, id: usize) -> Option<&Jelly> {
        self.jellies.iter().find(|j| j.id == id).map(|j| j.as_ref())
    }

    pub fn unfrozen_jelly(&mut self, id: usize) -> Option<&mut Jelly> {
        let parent_id = self.find_group(id);
        let mut target_idx = None;
        for idx in 0..self.jellies.len() {
            if self.jellies[idx].parent_id == parent_id {
                Arc::make_mut(&mut self.jellies[idx]);
                if self.jellies[idx].id == id {
                    target_idx = Some(idx);
                }
            }
        }
        target_idx.map(|idx| Arc::make_mut(&mut self.jellies[idx]))
    }

    pub fn find_group(&self, id: usize) -> usize {
        if let Some(jelly) = self.find_jelly_by_id(id) {
            jelly.parent_id
        } else {
            id
        }
    }

    pub fn link_group(&mut self, id1: usize, id2: usize) {
        let root1 = self.find_group(id1);
        let root2 = self.find_group(id2);
        if root1 != root2 {
            let target_ids: Vec<usize> = self.jellies.iter()
                .filter(|j| j.parent_id == root2)
                .map(|j| j.id)
                .collect();
            for id in target_ids {
                if let Some(jelly) = self.unfrozen_jelly(id) {
                    jelly.parent_id = root1;
                }
            }
            if let Some(hiddens) = &mut self.hiddens {
                for h in hiddens {
                    if h.jelly_id == Some(root2) {
                        h.jelly_id = Some(root1);
                    }
                }
            }
        }
    }

    pub fn can_move(&self, id: usize, dx: i32, dy: i32) -> Option<Stage> {
        let jelly = self.find_jelly_by_id(id)?;
        if jelly.locked {
            return None;
        }
        let mut moves = HashSet::new();
        if !self.can_move_recur(jelly.parent_id, dx, dy, &mut moves) {
            return None;
        }
        let mut next_stage = self.clone();
        next_stage.sorted_jellies_cache = None;
        next_stage.sorted_hiddens_cache = None;
        next_stage.move_jellies(&moves, dx, dy);
        Some(next_stage)
    }

    fn can_move_recur(&self, root_id: usize, dx: i32, dy: i32, moves: &mut HashSet<usize>) -> bool {
        if moves.contains(&root_id) {
            return true;
        }
        moves.insert(root_id);

        let group_jellies: Vec<&Jelly> = self.jellies.iter()
            .filter(|j| j.parent_id == root_id)
            .map(|j| j.as_ref())
            .collect();

        for jelly in &group_jellies {
            let new_x = jelly.x + dx;
            let new_y = jelly.y + dy;
            for i in 0..jelly.shape.lines().len() {
                let line = jelly.shape.lines()[i];
                let wall_y = new_y + i as i32;
                if wall_y < 0 || wall_y >= self.wall_lines.len() as i32 {
                    return false;
                }
                if (self.wall_lines[wall_y as usize] & (line << new_x)) != 0 {
                    return false;
                }
            }
        }

        for jelly in &group_jellies {
            let new_x = jelly.x + dx;
            let new_y = jelly.y + dy;

            for other in &self.jellies {
                if other.parent_id == root_id {
                    continue;
                }
                if moves.contains(&other.parent_id) {
                    continue;
                }

                if other.overlap(jelly, new_x, new_y) {
                    if other.locked {
                        return false;
                    }
                    if !self.can_move_recur(other.parent_id, dx, dy, moves) {
                        return false;
                    }
                }
            }
        }
        true
    }

    pub fn move_jellies(&mut self, moves: &HashSet<usize>, dx: i32, dy: i32) {
        let target_ids: Vec<usize> = self.jellies.iter()
            .filter(|j| moves.contains(&j.parent_id))
            .map(|j| j.id)
            .collect();
        for id in target_ids {
            if let Some(jelly) = self.unfrozen_jelly(id) {
                jelly.x += dx;
                jelly.y += dy;
            }
        }
    }

    pub fn free_fall(&mut self, fall_info: Option<FallInfo>) -> Option<FallInfo> {
        let mut w_lines = match &fall_info {
            Some(info) => info.wall_lines.clone(),
            None => self.wall_lines.clone(),
        };

        let mut j_list = match fall_info {
            Some(info) => info.jellies,
            None => {
                let mut list = self.jellies.clone();
                list.sort_by_key(|j| -(j.y + j.shape.h() - 1));
                list
            }
        };

        loop {
            let mut settled_any = false;
            let mut i = 0;
            while i < j_list.len() {
                let jelly = &j_list[i];
                let mut grounded = jelly.locked;

                if !grounded {
                    for j in 0..jelly.shape.lines().len() {
                        let line = jelly.shape.lines()[j];
                        let next_y = jelly.y + j as i32 + 1;
                        if next_y >= w_lines.len() as i32 || (w_lines[next_y as usize] & (line << jelly.x)) != 0 {
                            grounded = true;
                            break;
                        }
                    }
                }

                if grounded {
                    let group_id = jelly.parent_id;
                    let mut k = 0;
                    while k < j_list.len() {
                        if j_list[k].parent_id == group_id {
                            let settled_jelly = j_list.remove(k);
                            for j in 0..settled_jelly.shape.lines().len() {
                                let line = settled_jelly.shape.lines()[j];
                                w_lines[(settled_jelly.y + j as i32) as usize] |= line << settled_jelly.x;
                            }
                            settled_any = true;
                        } else {
                            k += 1;
                        }
                    }
                    if settled_any {
                        break;
                    }
                } else {
                    i += 1;
                }
            }

            if !settled_any {
                break;
            }
        }

        if j_list.is_empty() {
            return None;
        }

        let target_ids: Vec<usize> = j_list.iter().map(|j| j.id).collect();
        for id in target_ids {
            if let Some(jelly) = self.unfrozen_jelly(id) {
                jelly.y += 1;
            }
        }

        for idx in 0..j_list.len() {
            let id = j_list[idx].id;
            if let Some(new_arc) = self.jellies.iter().find(|j| j.id == id) {
                j_list[idx] = Arc::clone(new_arc);
            }
        }

        Some(FallInfo {
            wall_lines: w_lines,
            jellies: j_list,
        })
    }

    pub fn merge_jellies(&mut self) {
        let mut idx = 0;
        while idx < self.jellies.len() {
            let mut jelly = Arc::clone(&self.jellies[idx]);
            if jelly.color == BLACK {
                idx += 1;
                continue;
            }

            let mut other_idx = idx + 1;
            while other_idx < self.jellies.len() {
                let other = Arc::clone(&self.jellies[other_idx]);
                if other.color != jelly.color {
                    other_idx += 1;
                    continue;
                }

                if jelly.adjacent(&other) {
                    let other_root = other.parent_id;
                    let jelly_root = jelly.parent_id;

                    let other_jelly = self.jellies.remove(other_idx);
                    
                    let target_id = jelly.id;
                    if let Some(target_jelly) = self.unfrozen_jelly(target_id) {
                        target_jelly.merge(&other_jelly);
                    }

                    self.link_group(jelly_root, other_root);
                    jelly = Arc::clone(&self.jellies[idx]);
                    other_idx = idx; // 位置を戻して再チェック
                }
                other_idx += 1;
            }
            idx += 1;
        }

        // ロックされているゼリーと同じグループのゼリーはすべてロックする
        let locked_roots: HashSet<usize> = self.jellies.iter()
            .filter(|j| j.locked)
            .map(|j| j.parent_id)
            .collect();

        let lock_target_ids: Vec<usize> = self.jellies.iter()
            .filter(|j| locked_roots.contains(&j.parent_id) && !j.locked)
            .map(|j| j.id)
            .collect();

        for id in lock_target_ids {
            if let Some(jelly) = self.unfrozen_jelly(id) {
                jelly.locked = true;
            }
        }
    }

    pub fn apply_hiddens(&mut self) -> bool {
        if self.hiddens.is_none() {
            return false;
        }

        let mut hiddens = self.hiddens.clone().unwrap();
        let mut applied = false;
        let mut i = 0;
        while i < hiddens.len() {
            let hidden = hiddens[i];
            let mut hx = hidden.x;
            let mut hy = hidden.y;

            if let Some(j_id) = hidden.jelly_id {
                if let Some(owner) = self.find_jelly_by_id(j_id) {
                    hx += owner.x;
                    hy += owner.y;
                }
            }

            let mut hidden_removed = false;
            for j_idx in 0..self.jellies.len() {
                let jelly = Arc::clone(&self.jellies[j_idx]);
                if jelly.color == hidden.color && jelly.occupy_position(hx + hidden.dx, hy + hidden.dy) {
                    if self.apply_hidden(jelly.id, hidden, hx, hy) {
                        hiddens.remove(i);
                        applied = true;
                        hidden_removed = true;
                        break;
                    }
                }
            }

            if hidden_removed {
                continue;
            }
            i += 1;
        }

        if hiddens.is_empty() {
            self.hiddens = None;
        } else {
            self.hiddens = Some(hiddens);
        }

        applied
    }

    fn apply_hidden(&mut self, jelly_id: usize, hidden: Hidden, mut hx: i32, mut hy: i32) -> bool {
        let (_, _, parent_id) = {
            let jelly = self.find_jelly_by_id(jelly_id).unwrap();
            (jelly.x, jelly.y, jelly.parent_id)
        };

        let mut moves = HashSet::new();
        let updated = self.can_move_recur(parent_id, hidden.dx, hidden.dy, &mut moves);

        if !updated {
            let o_id = match hidden.jelly_id {
                Some(id) => id,
                None => return false,
            };
            let mut owner_moves = HashSet::new();
            let parent_id = self.find_jelly_by_id(o_id).unwrap().parent_id;
            let updated_owner = self.can_move_recur(parent_id, -hidden.dx, -hidden.dy, &mut owner_moves);
            if !updated_owner {
                return false;
            }

            self.move_jellies(&owner_moves, -hidden.dx, -hidden.dy);
            hx -= hidden.dx;
            hy -= hidden.dy;
        } else {
            self.move_jellies(&moves, hidden.dx, hidden.dy);
        }

        let appeared_locked = hidden.link && hidden.jelly_id.is_none();
        let single_pos = vec![Point::new(0, 0)];
        let appeared = Jelly::new(9999, hx + hidden.dx, hy + hidden.dy, hidden.color, JellyShape::register_shape(single_pos), appeared_locked);

        if let Some(target_jelly) = self.unfrozen_jelly(jelly_id) {
            target_jelly.merge(&appeared);
        }

        if let Some(o_id) = hidden.jelly_id {
            let owner_root = self.find_jelly_by_id(o_id).unwrap().parent_id;
            let jelly_root = self.find_jelly_by_id(jelly_id).unwrap().parent_id;

            if let Some(owner) = self.unfrozen_jelly(o_id) {
                owner.remove_hidden(hx - owner.x, hy - owner.y);
            }

            if hidden.link {
                self.link_group(owner_root, jelly_root);
            }
        }

        true
    }

    pub fn estimate_distance(&self) -> i32 {
        let mut color_jellies: HashMap<char, Vec<&Jelly>> = HashMap::new();
        for jelly in &self.jellies {
            if jelly.color == BLACK {
                continue;
            }
            color_jellies.entry(jelly.color).or_default().push(jelly);
        }

        let mut dist = 0;
        for list in color_jellies.values() {
            if list.len() < 2 {
                continue;
            }
            let jl = list.iter().min_by_key(|j| j.x).unwrap();
            let jr = list.iter().max_by_key(|j| j.x + j.shape.w()).unwrap();
            dist += std::cmp::max(jr.x - (jl.x + jl.shape.w()), 1);
        }

        if let Some(hiddens) = &self.hiddens {
            let mut d = 0;
            for hidden in hiddens {
                let mut hx = hidden.x;
                if let Some(o_id) = hidden.jelly_id {
                    if let Some(owner) = self.find_jelly_by_id(o_id) {
                        hx += owner.x;
                    }
                }

                if let Some(list) = color_jellies.get(&hidden.color) {
                    if list.is_empty() {
                        continue;
                    }
                    let jl = list.iter().min_by_key(|j| j.x).unwrap();
                    let jr = list.iter().max_by_key(|j| j.x + j.shape.w()).unwrap();

                    if hx < jl.x {
                        d += jl.x - hx;
                    } else if hx >= jr.x + jr.shape.w() {
                        d += hx - (jr.x + jr.shape.w());
                    } else {
                        d += 1;
                    }
                }
            }
            dist += d;
        }
        dist
    }

    pub fn make_lines(&self) -> Vec<String> {
        let width = self.width();
        let height = self.height();
        let mut grid = vec![vec![VACANT; width]; height];

        for y in 0..height {
            let line = self.wall_lines[y];
            for x in 0..width {
                if (line & (1 << x)) != 0 {
                    grid[y][x] = WALL;
                }
            }
        }

        for jelly in &self.jellies {
            let mut c = jelly.color;
            if c == BLACK {
                if let Some(bc) = jelly.black_char {
                    c = bc;
                }
            } else if jelly.locked {
                c = c.to_ascii_lowercase();
            }

            for p in jelly.shape.positions() {
                let px = (p.x + jelly.x) as usize;
                let py = (p.y + jelly.y) as usize;
                if py < height && px < width {
                    grid[py][px] = c;
                }
            }
        }

        grid.into_iter().map(|row| row.into_iter().collect()).collect()
    }
}

impl PartialEq for Stage {
    fn eq(&self, other: &Self) -> bool {
        if self.hash_code != other.hash_code {
            return false;
        }
        if self.wall_lines != other.wall_lines {
            return false;
        }

        let this_ref = self.sorted_jellies_cache.as_ref().unwrap();
        let other_ref = other.sorted_jellies_cache.as_ref().unwrap();

        if this_ref != other_ref {
            return false;
        }

        let this_h_ref = self.sorted_hiddens_cache.as_ref();
        let other_h_ref = other.sorted_hiddens_cache.as_ref();

        this_h_ref == other_h_ref
    }
}

impl std::hash::Hash for Stage {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        self.hash_code.hash(state);
    }
}
