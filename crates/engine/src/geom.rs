//! Geometry: integer canvas coordinates, sub-pixel points, sizes, rectangles, and the
//! pure screen↔canvas transform (SPEC §4 module 2, §5.4).

pub const MIN_DIM: u16 = 8;
pub const MAX_DIM: u16 = 256;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct Point {
    pub x: i32,
    pub y: i32,
}
impl Point {
    pub const fn new(x: i32, y: i32) -> Self {
        Point { x, y }
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct PointF {
    pub x: f32,
    pub y: f32,
}
impl PointF {
    pub const fn new(x: f32, y: f32) -> Self {
        PointF { x, y }
    }
    pub fn floor(self) -> Point {
        Point::new(self.x.floor() as i32, self.y.floor() as i32)
    }
    pub fn dist(self, o: PointF) -> f32 {
        let dx = self.x - o.x;
        let dy = self.y - o.y;
        (dx * dx + dy * dy).sqrt()
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Size {
    pub w: u16,
    pub h: u16,
}
impl Size {
    pub const fn new(w: u16, h: u16) -> Self {
        Size { w, h }
    }
    pub fn area(&self) -> usize {
        self.w as usize * self.h as usize
    }
    pub fn in_range(&self) -> bool {
        (MIN_DIM..=MAX_DIM).contains(&self.w) && (MIN_DIM..=MAX_DIM).contains(&self.h)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct IRect {
    pub x: i32,
    pub y: i32,
    pub w: u32,
    pub h: u32,
}
impl IRect {
    pub const fn new(x: i32, y: i32, w: u32, h: u32) -> Self {
        IRect { x, y, w, h }
    }
    pub fn from_size(s: Size) -> Self {
        IRect::new(0, 0, s.w as u32, s.h as u32)
    }
    pub fn right(&self) -> i32 {
        self.x + self.w as i32
    }
    pub fn bottom(&self) -> i32 {
        self.y + self.h as i32
    }
    pub fn is_empty(&self) -> bool {
        self.w == 0 || self.h == 0
    }
    pub fn contains(&self, p: Point) -> bool {
        p.x >= self.x && p.y >= self.y && p.x < self.right() && p.y < self.bottom()
    }
    /// Smallest rect covering both points (inclusive).
    pub fn bounding(a: Point, b: Point) -> Self {
        let (minx, maxx) = (a.x.min(b.x), a.x.max(b.x));
        let (miny, maxy) = (a.y.min(b.y), a.y.max(b.y));
        IRect::new(minx, miny, (maxx - minx + 1) as u32, (maxy - miny + 1) as u32)
    }
    pub fn union(&self, o: &IRect) -> IRect {
        if self.is_empty() {
            return *o;
        }
        if o.is_empty() {
            return *self;
        }
        let minx = self.x.min(o.x);
        let miny = self.y.min(o.y);
        let maxx = self.right().max(o.right());
        let maxy = self.bottom().max(o.bottom());
        IRect::new(minx, miny, (maxx - minx) as u32, (maxy - miny) as u32)
    }
    pub fn intersect(&self, o: &IRect) -> IRect {
        let minx = self.x.max(o.x);
        let miny = self.y.max(o.y);
        let maxx = self.right().min(o.right());
        let maxy = self.bottom().min(o.bottom());
        if maxx <= minx || maxy <= miny {
            IRect::new(0, 0, 0, 0)
        } else {
            IRect::new(minx, miny, (maxx - minx) as u32, (maxy - miny) as u32)
        }
    }
    /// Clamp this rect into `[0,w)×[0,h)`.
    pub fn clamp_to(&self, w: u32, h: u32) -> IRect {
        self.intersect(&IRect::new(0, 0, w, h))
    }
}

/// Pan + uniform zoom mapping between screen pixels and canvas pixels. Pure & unit-tested
/// (SPEC §5.4): "I tapped here but it drew there" bugs become data tests here.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Transform {
    pub pan_x: f32,
    pub pan_y: f32,
    pub zoom: f32,
}
impl Default for Transform {
    fn default() -> Self {
        Transform { pan_x: 0.0, pan_y: 0.0, zoom: 1.0 }
    }
}
impl Transform {
    pub fn screen_to_canvas(&self, p: PointF) -> PointF {
        PointF::new((p.x - self.pan_x) / self.zoom, (p.y - self.pan_y) / self.zoom)
    }
    pub fn canvas_to_screen(&self, p: PointF) -> PointF {
        PointF::new(p.x * self.zoom + self.pan_x, p.y * self.zoom + self.pan_y)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn transform_roundtrips() {
        let t = Transform { pan_x: 13.5, pan_y: -4.0, zoom: 3.25 };
        for &(x, y) in &[(0.0, 0.0), (10.0, 20.0), (-5.0, 7.5)] {
            let p = PointF::new(x, y);
            let back = t.screen_to_canvas(t.canvas_to_screen(p));
            assert!((back.x - p.x).abs() < 1e-4 && (back.y - p.y).abs() < 1e-4);
        }
    }

    #[test]
    fn rect_bounding_and_union() {
        let r = IRect::bounding(Point::new(2, 3), Point::new(5, 1));
        assert_eq!(r, IRect::new(2, 1, 4, 3));
        let u = IRect::new(0, 0, 2, 2).union(&IRect::new(4, 4, 2, 2));
        assert_eq!(u, IRect::new(0, 0, 6, 6));
    }

    #[test]
    fn rect_intersect_disjoint_is_empty() {
        assert!(IRect::new(0, 0, 2, 2).intersect(&IRect::new(5, 5, 2, 2)).is_empty());
    }
}
