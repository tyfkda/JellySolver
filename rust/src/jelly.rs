use crate::jelly_shape::JellyShape;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct Hidden {
    pub x: i32,
    pub y: i32,
    pub color: char,
    pub dx: i32,
    pub dy: i32,
    pub jelly_id: Option<usize>, // 親ゼリーのインデックス
    pub link: bool,
}

impl Hidden {
    pub fn new(x: i32, y: i32, color: char, dx: i32, dy: i32, jelly_id: Option<usize>, link: bool) -> Self {
        Self { x, y, color, dx, dy, jelly_id, link }
    }
}

#[derive(Clone, Debug, Eq)]
pub struct Jelly {
    pub id: usize,
    pub x: i32,
    pub y: i32,
    pub color: char,
    pub shape: JellyShape,
    pub locked: bool,
    pub black_char: Option<char>, // 黒ブロックの元の文字
    pub hiddens: Option<Vec<Hidden>>,
    pub parent_id: usize, // Union-Find連結管理用の親ID
}

impl Jelly {
    pub fn new(id: usize, x: i32, y: i32, color: char, shape: JellyShape, locked: bool) -> Self {
        Self {
            id,
            x,
            y,
            color,
            shape,
            locked,
            black_char: None,
            hiddens: None,
            parent_id: id,
        }
    }

    pub fn occupy_position(&self, px: i32, py: i32) -> bool {
        self.shape.occupy_position(px - self.x, py - self.y)
    }

    fn shift_left(val: i32, shift: i32) -> i32 {
        if shift >= 0 {
            val << shift
        } else {
            ((val as u32) >> (-shift)) as i32
        }
    }

    pub fn adjacent(&self, other: &Self) -> bool {
        if self.x + self.shape.w() < other.x || other.x + other.shape.w() < self.x ||
           self.y + self.shape.h() < other.y || other.y + other.shape.h() < self.y {
            return false;
        }

        let y0 = std::cmp::max(self.y - 1, other.y);
        let y1 = std::cmp::min(self.y + self.shape.h() + 1, other.y + other.shape.h());
        let dx = other.x - (self.x - 1);

        for y in y0..y1 {
            let this_adj = self.shape.adjacent_lines()[(y - (self.y - 1)) as usize];
            let other_line = other.shape.lines()[(y - other.y) as usize];
            if (this_adj & Self::shift_left(other_line, dx)) != 0 {
                return true;
            }
        }
        false
    }

    pub fn overlap(&self, other: &Self, newx: i32, newy: i32) -> bool {
        if self.x + self.shape.w() <= newx || newx + other.shape.w() <= self.x {
            return false;
        }

        let y0 = std::cmp::max(self.y, newy);
        let y1 = std::cmp::min(self.y + self.shape.h(), newy + other.shape.h());

        for y in y0..y1 {
            let this_line = self.shape.lines()[(y - self.y) as usize];
            let other_line = other.shape.lines()[(y - newy) as usize];
            if (Self::shift_left(this_line, self.x) & Self::shift_left(other_line, newx)) != 0 {
                return true;
            }
        }
        false
    }

    pub fn merge(&mut self, other: &Self) {
        let dx = other.x - self.x;
        let dy = other.y - self.y;
        self.x = std::cmp::min(self.x, other.x);
        self.y = std::cmp::min(self.y, other.y);
        self.shape = self.shape.concatenated(&other.shape, dx, dy);
        self.locked = self.locked || other.locked;
    }

    pub fn add_hidden(&mut self, hidden: Hidden) {
        let list = self.hiddens.get_or_insert_with(Vec::new);
        list.push(hidden);
    }

    pub fn remove_hidden(&mut self, hx: i32, hy: i32) {
        if let Some(list) = &mut self.hiddens {
            if let Some(pos) = list.iter().position(|h| h.x == hx && h.y == hy) {
                list.remove(pos);
            }
            if list.is_empty() {
                self.hiddens = None;
            }
        }
    }
}

impl Ord for Jelly {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        self.y.cmp(&other.y)
            .then_with(|| self.x.cmp(&other.x))
            .then_with(|| self.shape.h().cmp(&other.shape.h()))
            .then_with(|| self.shape.w().cmp(&other.shape.w()))
    }
}

impl PartialOrd for Jelly {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}

impl PartialEq for Jelly {
    fn eq(&self, other: &Self) -> bool {
        self.x == other.x &&
        self.y == other.y &&
        self.color == other.color &&
        self.locked == other.locked &&
        self.shape == other.shape &&
        self.hiddens == other.hiddens
    }
}

impl std::hash::Hash for Jelly {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        self.x.hash(state);
        self.y.hash(state);
        self.color.hash(state);
        self.locked.hash(state);
        self.shape.hash(state);
        self.hiddens.hash(state);
    }
}
