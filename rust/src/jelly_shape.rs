use std::sync::{Arc, OnceLock};
use crate::point::Point;

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct JellyShape {
    inner: Arc<JellyShapeInner>,
}

#[derive(Debug, PartialEq, Eq, Hash)]
struct JellyShapeInner {
    positions: Vec<Point>,
    w: i32,
    h: i32,
    lines: Vec<i32>,
    adjacent_lines: Vec<i32>,
}

static SHAPES: OnceLock<dashmap::DashMap<Vec<Point>, JellyShape>> = OnceLock::new();

fn get_shapes() -> &'static dashmap::DashMap<Vec<Point>, JellyShape> {
    SHAPES.get_or_init(|| dashmap::DashMap::new())
}

impl JellyShape {
    pub fn register_shape(positions: Vec<Point>) -> Self {
        let mut sorted = positions;
        sorted.sort();

        let shapes = get_shapes();

        if let Some(shape) = shapes.get(&sorted) {
            return shape.value().clone();
        }

        let mut max_w = 0;
        let mut max_h = 0;
        for p in &sorted {
            if p.x > max_w { max_w = p.x; }
            if p.y > max_h { max_h = p.y; }
        }
        let w = max_w + 1;
        let h = max_h + 1;

        let mut lines = vec![0; h as usize];
        for p in &sorted {
            lines[p.y as usize] |= 1 << p.x;
        }

        let mut adj = vec![0; (h + 2) as usize];
        for i in 0..lines.len() {
            let line = lines[i];
            adj[i] |= line << 1;
            adj[i + 1] |= line | (line << 2);
            adj[i + 2] |= line << 1;
        }

        let shape = JellyShape {
            inner: Arc::new(JellyShapeInner {
                positions: sorted.clone(),
                w,
                h,
                lines,
                adjacent_lines: adj,
            }),
        };

        shapes.insert(sorted, shape.clone());
        shape
    }

    pub fn positions(&self) -> &[Point] {
        &self.inner.positions
    }

    pub fn w(&self) -> i32 {
        self.inner.w
    }

    pub fn h(&self) -> i32 {
        self.inner.h
    }

    pub fn lines(&self) -> &[i32] {
        &self.inner.lines
    }

    pub fn adjacent_lines(&self) -> &[i32] {
        &self.inner.adjacent_lines
    }

    pub fn occupy_position(&self, x: i32, y: i32) -> bool {
        self.inner.positions.iter().any(|p| p.x == x && p.y == y)
    }

    pub fn concatenated(&self, other: &Self, mut dx: i32, mut dy: i32) -> Self {
        let mut new_positions = Vec::new();
        let mut offset_x = 0;
        let mut offset_y = 0;
        if dx < 0 {
            offset_x = -dx;
            dx = 0;
        }
        if dy < 0 {
            offset_y = -dy;
            dy = 0;
        }

        for p in &self.inner.positions {
            new_positions.push(Point::new(p.x + offset_x, p.y + offset_y));
        }
        for p in &other.inner.positions {
            new_positions.push(Point::new(p.x + dx, p.y + dy));
        }
        Self::register_shape(new_positions)
    }
}
