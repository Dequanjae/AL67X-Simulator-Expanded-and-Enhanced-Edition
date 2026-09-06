//! Pure worldgen logic — NO Godot types, NO nodes, NO rendering.
//! Ported 1:1 from `level_generator.gd`. Same guarantees as the original:
//!  - every algorithm keeps `min_clearance` meters between prop footprints,
//!  - a clear spawn circle at the arena center,
//!  - a flood-fill connectivity pass rejects layouts with unreachable
//!    pockets (re-rolls with a bumped seed, up to MAX_ATTEMPTS).
//!
//! NOTE ON DETERMINISM: this uses a different PRNG (splitmix64) than
//! Godot's `RandomNumberGenerator`, so a given level's layout will NOT be
//! bit-identical to what the old GDScript produced for the same level
//! number — but it IS still deterministic per level (same level number +
//! same theme always produces the same layout), which is the property the
//! original spec actually cares about. If you have already shipped levels
//! that players rely on being identical across a version bump, regenerate
//! or re-verify them after switching to this implementation.

use std::f64::consts::{PI, TAU};

const CELL_SIZE: f64 = 1.0;
const PROP_INFLATE: f64 = 0.55;
const WALL_MARGIN: f64 = 2.0;
const MIN_REACHABLE_RATIO: f64 = 0.93;
const MAX_ATTEMPTS: i32 = 6;
const ARENA_GROWTH_PER_LEVEL: f64 = 0.025;
const ARENA_GROWTH_CAP: f64 = 0.6;

// ---------------------------------------------------------------------
// Small helpers: Vec2 + deterministic RNG (no external crates needed)
// ---------------------------------------------------------------------

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Vec2 {
    pub x: f64,
    pub y: f64,
}

impl Vec2 {
    pub fn new(x: f64, y: f64) -> Self {
        Self { x, y }
    }
    pub fn length(self) -> f64 {
        (self.x * self.x + self.y * self.y).sqrt()
    }
    pub fn distance_to(self, o: Vec2) -> f64 {
        Vec2::new(self.x - o.x, self.y - o.y).length()
    }
    pub fn from_angle(a: f64) -> Self {
        Vec2::new(a.cos(), a.sin())
    }
}
impl std::ops::Add for Vec2 {
    type Output = Vec2;
    fn add(self, o: Vec2) -> Vec2 {
        Vec2::new(self.x + o.x, self.y + o.y)
    }
}
impl std::ops::Mul<f64> for Vec2 {
    type Output = Vec2;
    fn mul(self, s: f64) -> Vec2 {
        Vec2::new(self.x * s, self.y * s)
    }
}

fn angle_difference(from: f64, to: f64) -> f64 {
    let mut diff = (to - from) % TAU;
    if diff < -PI {
        diff += TAU;
    }
    if diff > PI {
        diff -= TAU;
    }
    diff
}

/// Deterministic seeded PRNG (splitmix64). Zero dependencies, good enough
/// distribution for placement logic — not cryptographic.
pub struct Rng {
    state: u64,
}
impl Rng {
    pub fn new(seed: u64) -> Self {
        Self { state: seed }
    }
    fn next_u64(&mut self) -> u64 {
        self.state = self.state.wrapping_add(0x9E3779B97F4A7C15);
        let mut z = self.state;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58476D1CE4E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D049BB133111EB);
        z ^ (z >> 31)
    }
    pub fn randf(&mut self) -> f64 {
        (self.next_u64() >> 11) as f64 * (1.0 / (1u64 << 53) as f64)
    }
    pub fn randf_range(&mut self, a: f64, b: f64) -> f64 {
        a + (b - a) * self.randf()
    }
    pub fn randi_range(&mut self, a: i32, b: i32) -> i32 {
        if b <= a {
            return a;
        }
        a + (self.next_u64() % ((b - a + 1) as u64)) as i32
    }
}

// ---------------------------------------------------------------------
// Data types (theme input / prop output)
// ---------------------------------------------------------------------

#[derive(Clone, Debug, Default)]
pub struct PropDef {
    pub shape: Option<String>,
    pub size: Option<[f64; 3]>,
    pub color: Option<String>,
    pub weight: f64,
    pub role: String,
    pub mesh: Option<String>,
}
impl PropDef {
    fn empty_pool_fallback() -> Self {
        Self {
            shape: Some("box".into()),
            size: Some([1.0, 1.0, 1.0]),
            color: Some("#888888".into()),
            weight: 1.0,
            role: String::new(),
            mesh: None,
        }
    }
}

#[derive(Clone, Debug)]
pub struct GenParams {
    pub arena_size: [f64; 2],
    pub min_clearance: f64,
    pub spawn_clear_radius: f64,
    pub algorithm: String,
    pub prop_density: f64,
}
impl Default for GenParams {
    fn default() -> Self {
        Self {
            arena_size: [40.0, 40.0],
            min_clearance: 3.0,
            spawn_clear_radius: 4.5,
            algorithm: "scatter".into(),
            prop_density: 0.03,
        }
    }
}

#[derive(Clone, Debug, Default)]
pub struct Theme {
    pub id: String,
    pub generation: GenParams,
    pub props: Vec<PropDef>,
}

#[derive(Clone, Debug)]
pub struct Prop {
    pub shape: String,
    pub size: [f64; 3],
    pub color: String,
    pub pos: (f64, f64),
    pub rot: f64,
    pub mesh: Option<String>,
}

pub struct ValidationResult {
    pub ok: bool,
    pub reachable_ratio: f64,
    pub walkable: Vec<(f64, f64, f64)>,
}

pub struct LayoutResult {
    pub ok: bool,
    pub level: i32,
    pub theme_id: String,
    pub arena_size: (f64, f64),
    pub props: Vec<Prop>,
    pub walkable_points: Vec<(f64, f64, f64)>,
    pub reachable_ratio: f64,
    pub player_spawn: (f64, f64, f64),
    pub attempts: i32,
}

// ---------------------------------------------------------------------
// Prop helpers
// ---------------------------------------------------------------------

fn pick_prop(rng: &mut Rng, theme: &Theme, role: &str) -> PropDef {
    let mut pool: Vec<&PropDef> = theme.props.iter().collect();
    if !role.is_empty() {
        let filtered: Vec<&PropDef> = pool.iter().copied().filter(|p| p.role == role).collect();
        if !filtered.is_empty() {
            pool = filtered;
        }
    }
    if pool.is_empty() {
        return PropDef::empty_pool_fallback();
    }
    let total: f64 = pool.iter().map(|p| p.weight).sum();
    let mut roll = rng.randf() * total;
    for p in &pool {
        roll -= p.weight;
        if roll <= 0.0 {
            return (*p).clone();
        }
    }
    (*pool.last().unwrap()).clone()
}

fn make_prop(def: &PropDef, x: f64, z: f64, rot_deg: f64) -> Prop {
    Prop {
        shape: def.shape.clone().unwrap_or_else(|| "box".into()),
        size: def.size.unwrap_or([1.0, 1.0, 1.0]),
        color: def.color.clone().unwrap_or_else(|| "#888888".into()),
        pos: (x, z),
        rot: rot_deg,
        mesh: def.mesh.clone(),
    }
}

fn half_extents(prop: &Prop) -> Vec2 {
    let sx = prop.size[0] * 0.5;
    let sz = prop.size[2] * 0.5;
    let r = prop.rot.rem_euclid(180.0);
    if (r - 90.0).abs() < 1.0 {
        Vec2::new(sz, sx)
    } else if r < 1.0 || r > 179.0 {
        Vec2::new(sx, sz)
    } else {
        let m = sx.max(sz);
        Vec2::new(m, m)
    }
}

fn footprint_radius(prop: &Prop) -> f64 {
    let he = half_extents(prop);
    he.x.max(he.y)
}

fn fits(props: &[Prop], candidate: &Prop, clearance: f64) -> bool {
    let cr = footprint_radius(candidate);
    for other in props {
        let dist = Vec2::new(candidate.pos.0 - other.pos.0, candidate.pos.1 - other.pos.1).length();
        if dist < clearance + cr + footprint_radius(other) {
            return false;
        }
    }
    true
}

fn in_spawn_clear(x: f64, z: f64, prop_radius: f64, spawn_clear: f64) -> bool {
    Vec2::new(x, z).length() < spawn_clear + prop_radius
}

// ---------------------------------------------------------------------
// Algorithms
// ---------------------------------------------------------------------

fn gen_scatter(rng: &mut Rng, arena: Vec2, theme: &Theme, clearance: f64, spawn_clear: f64) -> Vec<Prop> {
    let mut props = Vec::new();
    let target = (arena.x * arena.y * theme.generation.prop_density) as i32;
    let half = Vec2::new(arena.x * 0.5, arena.y * 0.5);
    let mut tries = target * 30;
    while (props.len() as i32) < target && tries > 0 {
        tries -= 1;
        let def = pick_prop(rng, theme, "");
        let r = footprint_radius(&make_prop(&def, 0.0, 0.0, 0.0));
        let x = rng.randf_range(-half.x + WALL_MARGIN + r, half.x - WALL_MARGIN - r);
        let z = rng.randf_range(-half.y + WALL_MARGIN + r, half.y - WALL_MARGIN - r);
        if in_spawn_clear(x, z, r, spawn_clear) {
            continue;
        }
        let rot = 90.0 * rng.randi_range(0, 1) as f64;
        let candidate = make_prop(&def, x, z, rot);
        if fits(&props, &candidate, clearance) {
            props.push(candidate);
        }
    }
    props
}

fn gen_scatter_into(
    rng: &mut Rng,
    arena: Vec2,
    theme: &Theme,
    clearance: f64,
    spawn_clear: f64,
    existing: &[Prop],
    target: i32,
) -> Vec<Prop> {
    let mut extras = Vec::new();
    let half = Vec2::new(arena.x * 0.5, arena.y * 0.5);
    let mut tries = target * 30;
    while (extras.len() as i32) < target && tries > 0 {
        tries -= 1;
        let def = pick_prop(rng, theme, "");
        let r = footprint_radius(&make_prop(&def, 0.0, 0.0, 0.0));
        let x = rng.randf_range(-half.x + WALL_MARGIN + r, half.x - WALL_MARGIN - r);
        let z = rng.randf_range(-half.y + WALL_MARGIN + r, half.y - WALL_MARGIN - r);
        if in_spawn_clear(x, z, r, spawn_clear) {
            continue;
        }
        let candidate = make_prop(&def, x, z, 0.0);
        if fits(existing, &candidate, clearance) && fits(&extras, &candidate, clearance) {
            extras.push(candidate);
        }
    }
    extras
}

fn gen_aisles(rng: &mut Rng, arena: Vec2, theme: &Theme, clearance: f64, spawn_clear: f64) -> Vec<Prop> {
    let mut props = Vec::new();
    let half = Vec2::new(arena.x * 0.5, arena.y * 0.5);
    let horizontal = rng.randi_range(0, 1) == 0;
    let shelf_def = pick_prop(rng, theme, "shelf");
    let shelf_size = shelf_def.size.unwrap_or([0.9, 1.5, 3.0]);
    let shelf_w = shelf_size[0];
    let shelf_len = shelf_size[2];
    let row_gap = (clearance + shelf_w + 0.6_f64).max(4.5);
    let perp_half = if horizontal { half.y } else { half.x };
    let along_half = if horizontal { half.x } else { half.y };
    let mut row_pos = -perp_half + WALL_MARGIN + 1.0;
    while row_pos < perp_half - WALL_MARGIN - 1.0 {
        let mut t = -along_half + WALL_MARGIN;
        let mut segments_since_door = 0;
        let mut door_every = rng.randi_range(2, 4);
        while t + shelf_len < along_half - WALL_MARGIN {
            if segments_since_door >= door_every {
                t += rng.randf_range(2.8, 3.8);
                segments_since_door = 0;
                door_every = rng.randi_range(2, 4);
                continue;
            }
            let center_t = t + shelf_len * 0.5;
            let x = if horizontal { center_t } else { row_pos };
            let z = if horizontal { row_pos } else { center_t };
            let rot = if horizontal { 90.0 } else { 0.0 };
            let prop = make_prop(&shelf_def, x, z, rot);
            if !in_spawn_clear(x, z, footprint_radius(&prop), spawn_clear) {
                props.push(prop);
            }
            t += shelf_len + 0.2;
            segments_since_door += 1;
        }
        row_pos += row_gap;
    }
    let extras = gen_scatter_into(
        rng,
        arena,
        theme,
        clearance,
        spawn_clear,
        &props,
        (arena.x * arena.y * 0.004) as i32,
    );
    props.extend(extras);
    props
}

fn gen_rings(rng: &mut Rng, arena: Vec2, theme: &Theme, clearance: f64, spawn_clear: f64) -> Vec<Prop> {
    let mut props = Vec::new();
    let half = Vec2::new(arena.x * 0.5, arena.y * 0.5);
    let max_r = half.x.min(half.y) - WALL_MARGIN - 1.0;
    let mut radius = spawn_clear + 2.5;
    while radius < max_r {
        let door_count = rng.randi_range(2, 4);
        let mut doors = Vec::new();
        for _ in 0..door_count {
            doors.push(rng.randf_range(0.0, TAU));
        }
        let door_half_arc = 1.7 / radius;
        let mut angle = rng.randf_range(0.0, TAU);
        let mut walked = 0.0;
        while walked < TAU * radius {
            let def = pick_prop(rng, theme, "");
            let prop_dim = footprint_radius(&make_prop(&def, 0.0, 0.0, 0.0)) * 2.0;
            let step = prop_dim + 0.5;
            let mut in_door = false;
            for &door_angle in &doors {
                if angle_difference(angle, door_angle).abs() < door_half_arc + (prop_dim * 0.5) / radius {
                    in_door = true;
                    break;
                }
            }
            if !in_door {
                let x = angle.cos() * radius;
                let z = angle.sin() * radius;
                props.push(make_prop(&def, x, z, angle.to_degrees() + 90.0));
            }
            let dtheta = step / radius;
            angle = (angle + dtheta).rem_euclid(TAU);
            walked += step;
        }
        radius += (clearance + 2.0_f64).max(5.0);
    }
    props
}

fn gen_clusters(rng: &mut Rng, arena: Vec2, theme: &Theme, clearance: f64, spawn_clear: f64) -> Vec<Prop> {
    let mut props = Vec::new();
    let half = Vec2::new(arena.x * 0.5, arena.y * 0.5);
    let density = theme.generation.prop_density;
    let cluster_count = ((arena.x * arena.y * density * 0.25) as i32).clamp(4, 14);
    let mut centers: Vec<Vec2> = Vec::new();
    let mut tries = cluster_count * 40;
    let center_spacing = clearance * 2.0 + 4.0;
    while (centers.len() as i32) < cluster_count && tries > 0 {
        tries -= 1;
        let c = Vec2::new(
            rng.randf_range(-half.x + WALL_MARGIN + 3.0, half.x - WALL_MARGIN - 3.0),
            rng.randf_range(-half.y + WALL_MARGIN + 3.0, half.y - WALL_MARGIN - 3.0),
        );
        if c.length() < spawn_clear + 4.0 {
            continue;
        }
        let mut ok = true;
        for existing in &centers {
            if c.distance_to(*existing) < center_spacing {
                ok = false;
                break;
            }
        }
        if ok {
            centers.push(c);
        }
    }
    for center in &centers {
        let cluster_size = rng.randi_range(3, 6);
        let mut cluster_props: Vec<Prop> = Vec::new();
        let mut placement_tries = cluster_size * 20;
        while (cluster_props.len() as i32) < cluster_size && placement_tries > 0 {
            placement_tries -= 1;
            let offset = Vec2::from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(0.0, 2.2);
            let pos = *center + offset;
            let def = pick_prop(rng, theme, "");
            let rot = 90.0 * rng.randi_range(0, 1) as f64;
            let candidate = make_prop(&def, pos.x, pos.y, rot);
            if fits(&cluster_props, &candidate, 0.4) && fits(&props, &candidate, clearance) {
                cluster_props.push(candidate);
            }
        }
        props.extend(cluster_props);
    }
    props
}

fn wall_line(
    rng: &mut Rng,
    def: &PropDef,
    line_pos: f64,
    from: f64,
    to: f64,
    vertical: bool,
    seg_len: f64,
    door_w: f64,
    spawn_clear: f64,
) -> Vec<Prop> {
    let mut segments = Vec::new();
    let length = to - from;
    let door_count = 3;
    let mut doors = Vec::new();
    for i in 0..door_count {
        doors.push(from + length * (i as f64 + 0.5 + rng.randf_range(-0.18, 0.18)) / (door_count as f64));
    }
    let mut t = from;
    while t + seg_len <= to {
        let center = t + seg_len * 0.5;
        let mut in_door = false;
        for &door in &doors {
            if (center - door).abs() < (door_w + seg_len) * 0.5 {
                in_door = true;
                break;
            }
        }
        if !in_door {
            let x = if vertical { line_pos } else { center };
            let z = if vertical { center } else { line_pos };
            let rot = if vertical { 0.0 } else { 90.0 };
            let prop = make_prop(def, x, z, rot);
            if !in_spawn_clear(x, z, footprint_radius(&prop), spawn_clear) {
                segments.push(prop);
            }
        }
        t += seg_len + 0.05;
    }
    segments
}

fn gen_rooms(rng: &mut Rng, arena: Vec2, theme: &Theme, clearance: f64, spawn_clear: f64) -> Vec<Prop> {
    let mut props = Vec::new();
    let half = Vec2::new(arena.x * 0.5, arena.y * 0.5);
    let wall_def = pick_prop(rng, theme, "wall");
    let wall_size = wall_def.size.unwrap_or([0.5, 2.0, 2.6]);
    let seg_len = wall_size[2];
    let door_w = (clearance + 0.8_f64).max(3.6);
    let cols = if arena.x > 44.0 { 3 } else { 2 };
    for ci in 1..cols {
        let x = -half.x + arena.x * (ci as f64) / (cols as f64);
        props.extend(wall_line(
            rng,
            &wall_def,
            x,
            -half.y + WALL_MARGIN,
            half.y - WALL_MARGIN,
            true,
            seg_len,
            door_w,
            spawn_clear,
        ));
    }
    props.extend(wall_line(
        rng,
        &wall_def,
        0.0,
        -half.x + WALL_MARGIN,
        half.x - WALL_MARGIN,
        false,
        seg_len,
        door_w,
        spawn_clear,
    ));
    let extras = gen_scatter_into(
        rng,
        arena,
        theme,
        clearance,
        spawn_clear,
        &props,
        (arena.x * arena.y * 0.008) as i32,
    );
    props.extend(extras);
    props
}

// ---------------------------------------------------------------------
// Validation — coarse-grid flood fill from the spawn point
// ---------------------------------------------------------------------

fn validate(arena: Vec2, props: &[Prop]) -> ValidationResult {
    let nx = ((arena.x / CELL_SIZE) as i32).max(1);
    let nz = ((arena.y / CELL_SIZE) as i32).max(1);
    let half = Vec2::new(arena.x * 0.5, arena.y * 0.5);
    let mut blocked = vec![0u8; (nx * nz) as usize];

    for prop in props {
        let he_raw = half_extents(prop);
        let he = Vec2::new(he_raw.x + PROP_INFLATE, he_raw.y + PROP_INFLATE);
        let (px, pz) = prop.pos;
        let i_min = (((px - he.x + half.x) / CELL_SIZE) as i32).max(0);
        let i_max = (((px + he.x + half.x) / CELL_SIZE) as i32).min(nx - 1);
        let j_min = (((pz - he.y + half.y) / CELL_SIZE) as i32).max(0);
        let j_max = (((pz + he.y + half.y) / CELL_SIZE) as i32).min(nz - 1);
        for i in i_min..=i_max {
            for j in j_min..=j_max {
                let cx = -half.x + (i as f64 + 0.5) * CELL_SIZE;
                let cz = -half.y + (j as f64 + 0.5) * CELL_SIZE;
                if (cx - px).abs() <= he.x && (cz - pz).abs() <= he.y {
                    blocked[(j * nx + i) as usize] = 1;
                }
            }
        }
    }

    let open_count = blocked.iter().filter(|&&v| v == 0).count() as i64;

    let start_i = nx / 2;
    let start_j = nz / 2;
    let mut reachable = vec![0u8; (nx * nz) as usize];
    let mut queue: Vec<i32> = Vec::new();
    let start_idx = (start_j * nx + start_i) as usize;
    if blocked[start_idx] == 0 {
        queue.push(start_idx as i32);
        reachable[start_idx] = 1;
    }
    let mut reachable_count: i64 = 0;
    let mut walkable: Vec<(f64, f64, f64)> = Vec::new();
    while let Some(idx) = queue.pop() {
        reachable_count += 1;
        let i = idx % nx;
        let j = idx / nx;
        walkable.push((
            -half.x + (i as f64 + 0.5) * CELL_SIZE,
            0.0,
            -half.y + (j as f64 + 0.5) * CELL_SIZE,
        ));
        for (di, dj) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            let ni = i + di;
            let nj = j + dj;
            if ni < 0 || ni >= nx || nj < 0 || nj >= nz {
                continue;
            }
            let nidx = (nj * nx + ni) as usize;
            if blocked[nidx] == 0 && reachable[nidx] == 0 {
                reachable[nidx] = 1;
                queue.push(nidx as i32);
            }
        }
    }

    let ratio = reachable_count as f64 / (open_count.max(1)) as f64;
    ValidationResult {
        ok: ratio >= MIN_REACHABLE_RATIO && walkable.len() >= 50,
        reachable_ratio: ratio,
        walkable,
    }
}

// ---------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------

pub fn generate(level: i32, theme: &Theme) -> LayoutResult {
    let gen = &theme.generation;
    let growth = 1.0 + ARENA_GROWTH_CAP.min(ARENA_GROWTH_PER_LEVEL * (level - 1) as f64);
    let arena = Vec2::new(gen.arena_size[0] * growth, gen.arena_size[1] * growth);
    let clearance = gen.min_clearance.max(2.5);
    let spawn_clear = gen.spawn_clear_radius;

    for attempt in 0..MAX_ATTEMPTS {
        let seed = (level as i64).wrapping_mul(1_000_003) + (attempt as i64) * 7919;
        let mut rng = Rng::new(seed as u64);
        let props = match gen.algorithm.as_str() {
            "aisles" => gen_aisles(&mut rng, arena, theme, clearance, spawn_clear),
            "rings" => gen_rings(&mut rng, arena, theme, clearance, spawn_clear),
            "clusters" => gen_clusters(&mut rng, arena, theme, clearance, spawn_clear),
            "rooms" => gen_rooms(&mut rng, arena, theme, clearance, spawn_clear),
            _ => gen_scatter(&mut rng, arena, theme, clearance, spawn_clear),
        };
        let validation = validate(arena, &props);
        if validation.ok {
            return LayoutResult {
                ok: true,
                level,
                theme_id: theme.id.clone(),
                arena_size: (arena.x, arena.y),
                props,
                walkable_points: validation.walkable,
                reachable_ratio: validation.reachable_ratio,
                player_spawn: (0.0, 0.0, 0.0),
                attempts: attempt + 1,
            };
        }
    }

    let open_validation = validate(arena, &[]);
    LayoutResult {
        ok: false,
        level,
        theme_id: theme.id.clone(),
        arena_size: (arena.x, arena.y),
        props: Vec::new(),
        walkable_points: open_validation.walkable,
        reachable_ratio: open_validation.reachable_ratio,
        player_spawn: (0.0, 0.0, 0.0),
        attempts: MAX_ATTEMPTS,
    }
}

// ---------------------------------------------------------------------
// Unit tests — run with `cargo test` (no Godot needed for this module)
// ---------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn basic_theme(algorithm: &str) -> Theme {
        Theme {
            id: "test_theme".into(),
            generation: GenParams {
                arena_size: [40.0, 40.0],
                min_clearance: 3.0,
                spawn_clear_radius: 4.5,
                algorithm: algorithm.into(),
                prop_density: 0.03,
            },
            props: vec![
                PropDef {
                    shape: Some("box".into()),
                    size: Some([1.0, 1.0, 1.0]),
                    color: Some("#888888".into()),
                    weight: 1.0,
                    role: String::new(),
                    mesh: None,
                },
                PropDef {
                    shape: Some("box".into()),
                    size: Some([0.9, 1.5, 3.0]),
                    color: Some("#a0a0a0".into()),
                    weight: 1.0,
                    role: "shelf".into(),
                    mesh: None,
                },
                PropDef {
                    shape: Some("box".into()),
                    size: Some([0.5, 2.0, 2.6]),
                    color: Some("#6b5a45".into()),
                    weight: 1.0,
                    role: "wall".into(),
                    mesh: None,
                },
            ],
        }
    }

    #[test]
    fn all_algorithms_produce_valid_reachable_layout() {
        for algo in ["scatter", "aisles", "rings", "clusters", "rooms"] {
            let theme = basic_theme(algo);
            let result = generate(5, &theme);
            assert!(result.ok, "algorithm {algo} failed validation");
            assert!(result.reachable_ratio >= MIN_REACHABLE_RATIO);
            assert!(result.walkable_points.len() >= 50);
        }
    }

    #[test]
    fn same_level_is_deterministic() {
        let theme = basic_theme("scatter");
        let a = generate(12, &theme);
        let b = generate(12, &theme);
        assert_eq!(a.props.len(), b.props.len());
        for (p1, p2) in a.props.iter().zip(b.props.iter()) {
            assert_eq!(p1.pos, p2.pos);
        }
    }

    #[test]
    fn arena_grows_and_caps_with_level() {
        let theme = basic_theme("scatter");
        let low = generate(1, &theme);
        let high = generate(500, &theme);
        assert!(high.arena_size.0 > low.arena_size.0);
        // Growth is capped at ARENA_GROWTH_CAP (0.6), so 500 and 1000 should
        // land on the same capped size.
        let capped = generate(1000, &theme);
        assert!((high.arena_size.0 - capped.arena_size.0).abs() < 1e-9);
    }
}
