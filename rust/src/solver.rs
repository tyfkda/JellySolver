use std::collections::{HashMap, HashSet, VecDeque, BinaryHeap};
use std::sync::{Arc, Mutex, Condvar};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::cmp::Reverse;
use std::thread;
use std::time::Duration;
use crate::jelly::Jelly;
use crate::stage::Stage;
use crate::consts::BLACK;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Move {
    pub x: i32,
    pub y: i32,
    pub dx: i32,
}

impl Move {
    pub fn new(x: i32, y: i32, dx: i32) -> Self {
        Self { x, y, dx }
    }
    pub fn to_string(&self) -> String {
        format!("[{}, {}, {}]", self.x, self.y, self.dx)
    }
}

#[derive(Clone, Debug)]
pub struct NodeHistory {
    pub prev_stage: Option<Stage>,
    pub move_op: Option<Move>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SearchNode {
    pub stage: Stage,
    pub step: i32,
    pub f_score: i32,
}

impl Ord for SearchNode {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        self.f_score.cmp(&other.f_score)
    }
}

impl PartialOrd for SearchNode {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}

pub struct ThreadSafePriorityQueue<T> {
    heap: Mutex<BinaryHeap<Reverse<T>>>,
    cond: Condvar,
}

impl<T: Ord> ThreadSafePriorityQueue<T> {
    pub fn new() -> Self {
        Self {
            heap: Mutex::new(BinaryHeap::new()),
            cond: Condvar::new(),
        }
    }

    pub fn push(&self, item: T) {
        let mut heap = self.heap.lock().unwrap();
        heap.push(Reverse(item));
        self.cond.notify_one();
    }

    pub fn pop(&self, timeout: Duration) -> Option<T> {
        let mut heap = self.heap.lock().unwrap();
        let limit = std::time::Instant::now() + timeout;
        while heap.is_empty() {
            let now = std::time::Instant::now();
            if now >= limit {
                break;
            }
            let remaining = limit - now;
            let (new_heap, result) = self.cond.wait_timeout(heap, remaining).unwrap();
            heap = new_heap;
            if result.timed_out() {
                break;
            }
        }
        heap.pop().map(|Reverse(item)| item)
    }

    pub fn size(&self) -> usize {
        self.heap.lock().unwrap().len()
    }

    pub fn is_empty(&self) -> bool {
        self.heap.lock().unwrap().is_empty()
    }
}

pub struct ThreadSafeQueue<T> {
    queue: Mutex<VecDeque<T>>,
    cond: Condvar,
}

impl<T> ThreadSafeQueue<T> {
    pub fn new() -> Self {
        Self {
            queue: Mutex::new(VecDeque::new()),
            cond: Condvar::new(),
        }
    }

    pub fn push(&self, item: T) {
        let mut queue = self.queue.lock().unwrap();
        queue.push_back(item);
        self.cond.notify_one();
    }

    pub fn pop(&self, timeout: Duration) -> Option<T> {
        let mut queue = self.queue.lock().unwrap();
        let limit = std::time::Instant::now() + timeout;
        while queue.is_empty() {
            let now = std::time::Instant::now();
            if now >= limit {
                break;
            }
            let remaining = limit - now;
            let (new_queue, result) = self.cond.wait_timeout(queue, remaining).unwrap();
            queue = new_queue;
            if result.timed_out() {
                break;
            }
        }
        queue.pop_front()
    }

    pub fn size(&self) -> usize {
        self.queue.lock().unwrap().len()
    }

    pub fn is_empty(&self) -> bool {
        self.queue.lock().unwrap().is_empty()
    }
}

pub struct Solver {
    no_prune: bool,
    use_bfs: bool,
    quiet: bool,
    parallel: bool,
    check_count: usize,
    constraints: Option<HashMap<char, i32>>,
    maxy: i32,
}

impl Solver {
    pub fn new(no_prune: bool, use_bfs: bool, quiet: bool, parallel: bool) -> Self {
        Self {
            no_prune,
            use_bfs,
            quiet,
            parallel,
            check_count: 0,
            constraints: None,
            maxy: 0,
        }
    }

    pub fn check_count(&self) -> usize {
        self.check_count
    }

    pub fn solve(&mut self, stage: Stage) -> Option<Vec<Move>> {
        if !self.no_prune {
            self.detect_constraint(&stage);
        }

        if self.parallel {
            self.solve_parallel(stage)
        } else {
            self.solve_sequential(stage)
        }
    }

    fn solve_sequential(&mut self, mut stage: Stage) -> Option<Vec<Move>> {
        if !self.use_bfs {
            stage.distance = stage.estimate_distance();
        }
        stage.freeze();

        // 優先度付きキューと探索進行
        let mut que_bfs = VecDeque::new();
        let mut que_astar = BinaryHeap::new();

        let start_node = SearchNode {
            stage: stage.clone(),
            step: 0,
            f_score: if self.use_bfs { 0 } else { stage.distance },
        };

        if self.use_bfs {
            que_bfs.push_back(start_node);
        } else {
            que_astar.push(Reverse(start_node));
        }

        let mut nodes = HashMap::new();
        nodes.insert(stage.clone(), NodeHistory { prev_stage: None, move_op: None });

        let mut check_count = 0;

        while (self.use_bfs && !que_bfs.is_empty()) || (!self.use_bfs && !que_astar.is_empty()) {
            let node = if self.use_bfs {
                que_bfs.pop_front().unwrap()
            } else {
                que_astar.pop().unwrap().0
            };

            let current_stage = node.stage;
            let step = node.step;
            check_count += 1;

            if !self.quiet && check_count % 1000 == 0 {
                eprint!("\rCheck={}, left={}\x1b[0K", check_count, if self.use_bfs { que_bfs.len() } else { que_astar.len() });
            }

            if !self.no_prune && self.unsolvable(&current_stage) {
                continue;
            }

            if current_stage.solved() {
                self.check_count = check_count;
                if !self.quiet {
                    eprintln!("\rSolved!\x1b[0K");
                }
                return Some(Self::extract_moves(&nodes, &current_stage));
            }

            let next_step = step + 1;
            self.enumerate_next(&current_stage, |next_stage, move_op| {
                let mut ns = next_stage;
                ns.freeze();
                if !nodes.contains_key(&ns) {
                    nodes.insert(ns.clone(), NodeHistory {
                        prev_stage: Some(current_stage.clone()),
                        move_op: Some(move_op),
                    });
                    if !self.use_bfs {
                        ns.distance = ns.estimate_distance();
                    }
                    let next_node = SearchNode {
                        stage: ns.clone(),
                        step: next_step,
                        f_score: if self.use_bfs { 0 } else { ns.distance + next_step },
                    };
                    if self.use_bfs {
                        que_bfs.push_back(next_node);
                    } else {
                        que_astar.push(Reverse(next_node));
                    }
                }
            });
        }

        self.check_count = check_count;
        None
    }

    fn solve_parallel(&mut self, mut stage: Stage) -> Option<Vec<Move>> {
        if !self.use_bfs {
            stage.distance = stage.estimate_distance();
        }
        stage.freeze();

        let que_bfs = Arc::new(ThreadSafeQueue::new());
        let que_astar = Arc::new(ThreadSafePriorityQueue::new());

        let start_node = SearchNode {
            stage: stage.clone(),
            step: 0,
            f_score: if self.use_bfs { 0 } else { stage.distance },
        };

        if self.use_bfs {
            que_bfs.push(start_node);
        } else {
            que_astar.push(start_node);
        }

        let nodes = Arc::new(dashmap::DashMap::new());
        nodes.insert(stage.clone(), NodeHistory { prev_stage: None, move_op: None });

        let num_threads = std::thread::available_parallelism().map(|n| n.get()).unwrap_or(4);
        let active_workers = Arc::new(AtomicUsize::new(0));
        let global_check_count = Arc::new(AtomicUsize::new(0));
        let goal_stage = Arc::new(Mutex::new(None));

        let cv_lock = Arc::new((Mutex::new(false), Condvar::new()));
        let mut threads = Vec::new();

        for _ in 0..num_threads {
            let que_bfs = Arc::clone(&que_bfs);
            let que_astar = Arc::clone(&que_astar);
            let nodes = Arc::clone(&nodes);
            let active_workers = Arc::clone(&active_workers);
            let global_check_count = Arc::clone(&global_check_count);
            let goal_stage = Arc::clone(&goal_stage);
            let cv_lock = Arc::clone(&cv_lock);
            let use_bfs = self.use_bfs;
            let quiet = self.quiet;
            let no_prune = self.no_prune;

            let constraints = self.constraints.clone();
            let maxy = self.maxy;

            threads.push(thread::spawn(move || {
                let unsolvable_local = |stage: &Stage| -> bool {
                    let mut consts = constraints.clone();
                    let mut up = 0;

                    if let Some(hiddens) = &stage.hiddens {
                        let mut current_consts = consts.unwrap_or_default();
                        for hidden in hiddens {
                            if hidden.dy <= 0 {
                                up += 1;
                            }
                            if hidden.jelly_id.is_some() || hidden.link {
                                continue;
                            }
                            let y = hidden.y + hidden.dy;
                            if y >= maxy {
                                continue;
                            }
                            let entry = current_consts.entry(hidden.color).or_insert(y);
                            if y < *entry {
                                *entry = y;
                            }
                        }
                        consts = if current_consts.is_empty() { None } else { Some(current_consts) };
                    }

                    let const_map = match &consts {
                        Some(map) => map,
                        None => return false,
                    };

                    let mut color_heights = HashMap::new();
                    for jelly in &stage.jellies {
                        if jelly.color == BLACK || jelly.locked || !const_map.contains_key(&jelly.color) {
                            continue;
                        }
                        *color_heights.entry(jelly.color).or_insert(0) += jelly.shape.h();
                    }

                    for jelly in &stage.jellies {
                        if jelly.color == BLACK || jelly.locked || !const_map.contains_key(&jelly.color) {
                            continue;
                        }
                        let h = *color_heights.get(&jelly.color).unwrap_or(&0);
                        if let Some(&limit_y) = const_map.get(&jelly.color) {
                            if jelly.y - h - up >= limit_y {
                                return true;
                            }
                        }
                    }
                    false
                };

                let enumerate_next_local = |stage: &Stage, mut callback: Box<dyn FnMut(Stage, Move)>| {
                    let mut skips = HashSet::new();
                    for jelly in &stage.jellies {
                        if skips.contains(&jelly.id) {
                            continue;
                        }
                        for j in 0..2 {
                            let dx = j * 2 - 1;
                            if let Some(updated) = Solver::move_jelly_static(stage, jelly, dx) {
                                let top = jelly.shape.positions()[0];
                                let move_op = Move::new(jelly.x + top.x, jelly.y + top.y, dx);
                                callback(updated, move_op);
                            }
                        }

                        // グループのゼリーをスキップ対象へ
                        let group_id = jelly.parent_id;
                        for other in &stage.jellies {
                            if other.parent_id == group_id {
                                skips.insert(other.id);
                            }
                        }
                    }
                };

                while goal_stage.lock().unwrap().is_none() {
                    let node = if use_bfs {
                        que_bfs.pop(Duration::from_millis(10))
                    } else {
                        que_astar.pop(Duration::from_millis(10))
                    };

                    if node.is_none() {
                        let is_empty = if use_bfs { que_bfs.is_empty() } else { que_astar.is_empty() };
                        if active_workers.load(Ordering::Relaxed) == 0 && is_empty {
                            let (lock, cvar) = &*cv_lock;
                            let mut finished = lock.lock().unwrap();
                            *finished = true;
                            cvar.notify_all();
                            break;
                        }
                        continue;
                    }

                    let node = node.unwrap();
                    active_workers.fetch_add(1, Ordering::Relaxed);

                    let current_stage = node.stage;
                    let step = node.step;
                    let current_check = global_check_count.fetch_add(1, Ordering::Relaxed) + 1;

                    if !quiet && current_check % 1000 == 0 {
                        let que_len = if use_bfs { que_bfs.size() } else { que_astar.size() };
                        eprint!("\rCheck={}, left={}\x1b[0K", current_check, que_len);
                    }

                    if !no_prune && unsolvable_local(&current_stage) {
                        active_workers.fetch_sub(1, Ordering::Relaxed);
                        continue;
                    }

                    if current_stage.solved() {
                        let mut goal = goal_stage.lock().unwrap();
                        if goal.is_none() {
                            *goal = Some(current_stage.clone());
                        }
                        active_workers.fetch_sub(1, Ordering::Relaxed);
                        let (lock, cvar) = &*cv_lock;
                        let mut finished = lock.lock().unwrap();
                        *finished = true;
                        cvar.notify_all();
                        break;
                    }

                    let next_step = step + 1;
                    let current_stage_clone = current_stage.clone();
                    let que_bfs_clone = Arc::clone(&que_bfs);
                    let que_astar_clone = Arc::clone(&que_astar);
                    let nodes_clone = Arc::clone(&nodes);
                    enumerate_next_local(&current_stage, Box::new(move |next_stage, move_op| {
                        let mut ns = next_stage;
                        ns.freeze();

                        use dashmap::mapref::entry::Entry;
                        match nodes_clone.entry(ns.clone()) {
                            Entry::Vacant(e) => {
                                e.insert(NodeHistory {
                                    prev_stage: Some(current_stage_clone.clone()),
                                    move_op: Some(move_op),
                                });
                                if !use_bfs {
                                    ns.distance = ns.estimate_distance();
                                }
                                let next_node = SearchNode {
                                    stage: ns.clone(),
                                    step: next_step,
                                    f_score: if use_bfs { 0 } else { ns.distance + next_step },
                                };
                                if use_bfs {
                                    que_bfs_clone.push(next_node);
                                } else {
                                    que_astar_clone.push(next_node);
                                }
                            }
                            Entry::Occupied(_) => {}
                        }
                    }));

                    active_workers.fetch_sub(1, Ordering::Relaxed);
                }
            }));
        }

        // 完了を待機
        let (lock, cvar) = &*cv_lock;
        let mut finished = lock.lock().unwrap();
        while !*finished {
            let is_empty = if self.use_bfs { que_bfs.is_empty() } else { que_astar.is_empty() };
            if active_workers.load(Ordering::Relaxed) == 0 && is_empty {
                break;
            }
            finished = cvar.wait_timeout(finished, Duration::from_millis(100)).unwrap().0;
        }

        self.check_count = global_check_count.load(Ordering::Relaxed);
        let final_goal = goal_stage.lock().unwrap().clone();

        if let Some(goal) = final_goal {
            if !self.quiet {
                eprintln!("\rSolved!\x1b[0K");
            }
            let moves = Self::extract_moves_dashmap(&nodes, &goal);
            Some(moves)
        } else {
            None
        }
    }

    fn extract_moves(nodes: &HashMap<Stage, NodeHistory>, goal_stage: &Stage) -> Vec<Move> {
        let mut moves = Vec::new();
        let mut curr = goal_stage;
        while let Some(history) = nodes.get(curr) {
            if let Some(move_op) = history.move_op {
                moves.push(move_op);
            }
            if let Some(prev) = &history.prev_stage {
                curr = prev;
            } else {
                break;
            }
        }
        moves.reverse();
        moves
    }

    fn extract_moves_dashmap(nodes: &dashmap::DashMap<Stage, NodeHistory>, goal_stage: &Stage) -> Vec<Move> {
        let mut moves = Vec::new();
        let mut curr = goal_stage.clone();
        while let Some(history) = nodes.get(&curr) {
            if let Some(move_op) = history.move_op {
                moves.push(move_op);
            }
            if let Some(prev) = &history.prev_stage {
                curr = prev.clone();
            } else {
                break;
            }
        }
        moves.reverse();
        moves
    }

    pub fn enumerate_next<F>(&self, stage: &Stage, mut callback: F)
    where
        F: FnMut(Stage, Move),
    {
        let mut skips = HashSet::new();
        for jelly in &stage.jellies {
            if skips.contains(&jelly.id) {
                continue;
            }
            for j in 0..2 {
                let dx = j * 2 - 1;
                if let Some(updated) = Self::move_jelly_static(stage, jelly, dx) {
                    let top = jelly.shape.positions()[0];
                    let move_op = Move::new(jelly.x + top.x, jelly.y + top.y, dx);
                    callback(updated, move_op);
                }
            }

            let group_id = jelly.parent_id;
            for other in &stage.jellies {
                if other.parent_id == group_id {
                    skips.insert(other.id);
                }
            }
        }
    }

    pub fn move_jelly_static(stage: &Stage, jelly: &Jelly, dx: i32) -> Option<Stage> {
        let mut updated = stage.can_move(jelly.id, dx, 0)?;

        loop {
            let mut fall_info = None;
            loop {
                let next_fall = updated.free_fall(fall_info);
                if next_fall.is_none() {
                    break;
                }
                fall_info = next_fall;
            }
            updated.merge_jellies();
            if !updated.apply_hiddens() {
                break;
            }
        }
        Some(updated)
    }

    fn detect_constraint(&mut self, stage: &Stage) {
        let mut constraints = HashMap::new();
        let height = stage.height() as i32;
        let width = stage.width() as i32;
        let mut maxy = height - 1;

        loop {
            let wall_line = stage.wall_lines[maxy as usize];
            if wall_line != (1 << width) - 1 {
                let mut vacant = false;
                for x in 1..(width - 1) {
                    if (wall_line & (1 << x)) != 0 {
                        continue;
                    }
                    let jelly = stage.jellies.iter()
                        .find(|j| j.occupy_position(x, maxy));
                    if jelly.is_none() || !jelly.unwrap().locked {
                        vacant = true;
                        break;
                    }
                }
                if vacant {
                    break;
                }
            }
            maxy -= 1;
            if maxy < 0 {
                break;
            }
        }

        let mut sorted_jellies = stage.jellies.clone();
        sorted_jellies.sort();

        for jelly in &sorted_jellies {
            if jelly.y >= maxy {
                break;
            }
            if jelly.color == BLACK || !jelly.locked {
                continue;
            }
            let mut y = jelly.y + jelly.shape.h();

            let mut walls = true;
            for dx in 0..jelly.shape.w() {
                if (stage.wall_lines[y as usize] & (1 << (jelly.x + dx))) == 0 {
                    walls = false;
                    break;
                }
            }
            if walls {
                y -= 1;
            }

            let entry = constraints.entry(jelly.color).or_insert(y);
            if y < *entry {
                *entry = y;
            }
        }

        if let Some(hiddens) = &stage.hiddens {
            for hidden in hiddens {
                if hidden.jelly_id.is_none() && hidden.link {
                    let y = hidden.y + hidden.dy;
                    if y >= maxy {
                        continue;
                    }
                    let entry = constraints.entry(hidden.color).or_insert(y);
                    if y < *entry {
                        *entry = y;
                    }
                }
            }
        }

        self.constraints = if constraints.is_empty() { None } else { Some(constraints) };
        self.maxy = maxy;
    }

    fn unsolvable(&self, stage: &Stage) -> bool {
        let mut consts = self.constraints.clone();
        let mut up = 0;

        if let Some(hiddens) = &stage.hiddens {
            let mut current_consts = consts.unwrap_or_default();
            for hidden in hiddens {
                if hidden.dy <= 0 {
                    up += 1;
                }
                if hidden.jelly_id.is_some() || hidden.link {
                    continue;
                }
                let y = hidden.y + hidden.dy;
                if y >= self.maxy {
                    continue;
                }
                let entry = current_consts.entry(hidden.color).or_insert(y);
                if y < *entry {
                    *entry = y;
                }
            }
            consts = if current_consts.is_empty() { None } else { Some(current_consts) };
        }

        let const_map = match &consts {
            Some(map) => map,
            None => return false,
        };

        let mut color_heights = HashMap::new();
        for jelly in &stage.jellies {
            if jelly.color == BLACK || jelly.locked || !const_map.contains_key(&jelly.color) {
                continue;
            }
            *color_heights.entry(jelly.color).or_insert(0) += jelly.shape.h();
        }

        for jelly in &stage.jellies {
            if jelly.color == BLACK || jelly.locked || !const_map.contains_key(&jelly.color) {
                continue;
            }
            let h = *color_heights.get(&jelly.color).unwrap_or(&0);
            if let Some(&limit_y) = const_map.get(&jelly.color) {
                if jelly.y - h - up >= limit_y {
                    return true;
                }
            }
        }

        false
    }
}
