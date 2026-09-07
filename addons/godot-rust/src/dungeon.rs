// dungeon.rs — deterministic tile-grid dungeon generator (electric-motor-shop).
// Source: deterministic_dungeon_worldgen_package (ChatGPT-authored spec),
// integrated per its AI_AGENT_INSTRUCTIONS: exposed through the EXISTING
// GDExtension bridge, adapted to the project's prop-based rendering.
// Tile IDs: 0 = wall, 1 = floor, 2 = door.

//
// Deterministic procedural dungeon generator for the electric-motor-shop
// horde shooter.
//
// SAME seed + SAME level + SAME generator version = SAME layout.
//
// Tile IDs:
//   0 = Wall
//   1 = Floor
//   2 = Door
//
// This module intentionally contains NO Godot rendering code.
// The Godot/GDScript side should render the returned tile grid.
//
// Recommended future extensions:
// - semantic room types
// - prop spawn points
// - enemy spawn points
// - deterministic loot points
// - separate RNG streams for layout/props/enemies

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RoomShape {
    Rectangle,
    LShape,
    Cross,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RoomType {
    MainWorkshop,
    MotorRepair,
    Storage,
    PartsRoom,
    Office,
    ElectricalRoom,
    BreakRoom,
    LoadingBay,
}

#[derive(Clone, Copy, Debug)]
pub struct Room {
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
    pub shape: RoomShape,
    pub room_type: RoomType,
}

#[derive(Clone, Copy, Debug)]
pub struct Point {
    pub x: i32,
    pub y: i32,
}

#[derive(Debug)]
pub struct Dungeon {
    pub width: i32,
    pub height: i32,
    pub tiles: Vec<u8>,
    pub rooms: Vec<Room>,
    pub player_start: Point,
    pub enemy_spawn_points: Vec<Point>,
}

impl Dungeon {
    pub fn new(width: i32, height: i32) -> Self {
        Self {
            width,
            height,
            tiles: vec![0; (width * height) as usize],
            rooms: Vec::new(),
            player_start: Point { x: 0, y: 0 },
            enemy_spawn_points: Vec::new(),
        }
    }

    pub fn get(&self, x: i32, y: i32) -> u8 {
        if x < 0 || y < 0 || x >= self.width || y >= self.height {
            return 0;
        }
        self.tiles[(y * self.width + x) as usize]
    }

    pub fn set(&mut self, x: i32, y: i32, tile: u8) {
        if x < 0 || y < 0 || x >= self.width || y >= self.height {
            return;
        }
        self.tiles[(y * self.width + x) as usize] = tile;
    }
}

// Small deterministic RNG. No OS/system randomness is used.
struct SimpleRng {
    state: u64,
}

impl SimpleRng {
    fn new(seed: u64) -> Self {
        Self {
            state: if seed == 0 { 0x1234_5678_9ABC_DEF0 } else { seed },
        }
    }

    fn next_u32(&mut self) -> u32 {
        self.state ^= self.state << 13;
        self.state ^= self.state >> 7;
        self.state ^= self.state << 17;
        self.state as u32
    }

    fn range(&mut self, min: i32, max: i32) -> i32 {
        if max <= min {
            return min;
        }
        min + (self.next_u32() % (max - min) as u32) as i32
    }

    fn chance(&mut self, percent: u32) -> bool {
        self.next_u32() % 100 < percent
    }
}

fn mix_seed(seed: u64, level: u32) -> u64 {
    seed.wrapping_add((level as u64).wrapping_mul(0x9E37_79B9_7F4A_7C15))
        .wrapping_mul(6_364_136_223_846_793_005)
        .wrapping_add(1_442_695_040_888_963_407)
}

fn level_settings(level: u32) -> (i32, i32, i32, u32, i32) {
    let level = level.max(1);

    // Gradually grows the dungeon. Min 3 rooms keeps early levels playable
    // (a 1-room dungeon had too little walkable space for the game's
    // pickups + horde density).
    let min_rooms = (2 + ((level as i32 - 1) / 2)).max(3);
    let max_rooms = (3 + level as i32).max(min_rooms + 1);

    // Bigger rooms at higher levels; floor at 7 so even early rooms feel
    // like shop sections, not closets.
    let max_room_size = (8 + level as i32 / 2).min(18).max(7);

    // Irregular rooms become more common.
    let irregular_chance = (level * 6).min(65);

    // Extra connections make high-level layouts less linear.
    let extra_connections = (level as i32 / 3).min(8);

    (
        min_rooms,
        max_rooms,
        max_room_size,
        irregular_chance,
        extra_connections,
    )
}

fn rooms_overlap(a: Room, b: Room, padding: i32) -> bool {
    a.x - padding < b.x + b.width
        && a.x + a.width + padding > b.x
        && a.y - padding < b.y + b.height
        && a.y + a.height + padding > b.y
}

fn room_center(room: Room) -> Point {
    Point {
        x: room.x + room.width / 2,
        y: room.y + room.height / 2,
    }
}

fn carve_rectangle(dungeon: &mut Dungeon, x: i32, y: i32, width: i32, height: i32) {
    for yy in y..y + height {
        for xx in x..x + width {
            dungeon.set(xx, yy, 1);
        }
    }
}

fn carve_l_room(dungeon: &mut Dungeon, room: Room) {
    let half_width = room.width / 2;
    let half_height = room.height / 2;

    carve_rectangle(dungeon, room.x, room.y, room.width, half_height);
    carve_rectangle(dungeon, room.x, room.y, half_width, room.height);
}

fn carve_cross_room(dungeon: &mut Dungeon, room: Room) {
    let cx = room.x + room.width / 2;
    let cy = room.y + room.height / 2;

    carve_rectangle(dungeon, room.x, cy - 1, room.width, 3);
    carve_rectangle(dungeon, cx - 1, room.y, 3, room.height);
}

fn carve_room(dungeon: &mut Dungeon, room: Room) {
    match room.shape {
        RoomShape::Rectangle => {
            carve_rectangle(dungeon, room.x, room.y, room.width, room.height);
        }
        RoomShape::LShape => carve_l_room(dungeon, room),
        RoomShape::Cross => carve_cross_room(dungeon, room),
    }
}

fn carve_horizontal(dungeon: &mut Dungeon, x1: i32, x2: i32, y: i32) {
    let min_x = x1.min(x2);
    let max_x = x1.max(x2);

    for x in min_x..=max_x {
        dungeon.set(x, y, 1);
        if y + 1 < dungeon.height {
            dungeon.set(x, y + 1, 1);
        }
    }
}

fn carve_vertical(dungeon: &mut Dungeon, y1: i32, y2: i32, x: i32) {
    let min_y = y1.min(y2);
    let max_y = y1.max(y2);

    for y in min_y..=max_y {
        dungeon.set(x, y, 1);
        if x + 1 < dungeon.width {
            dungeon.set(x + 1, y, 1);
        }
    }
}

fn connect_rooms(dungeon: &mut Dungeon, a: Room, b: Room, rng: &mut SimpleRng) {
    let ac = room_center(a);
    let bc = room_center(b);

    if rng.chance(50) {
        carve_horizontal(dungeon, ac.x, bc.x, ac.y);
        carve_vertical(dungeon, ac.y, bc.y, bc.x);
    } else {
        carve_vertical(dungeon, ac.y, bc.y, ac.x);
        carve_horizontal(dungeon, ac.x, bc.x, bc.y);
    }

    // The room centers are deliberately used here as simple door markers.
    // A later production pass can place doors precisely on room boundaries.
    dungeon.set(ac.x, ac.y, 2);
    dungeon.set(bc.x, bc.y, 2);
}

fn choose_room_type(index: usize, level: u32, rng: &mut SimpleRng) -> RoomType {
    if index == 0 {
        return RoomType::MainWorkshop;
    }

    // Higher levels unlock more room variety.
    let choices: &[RoomType] = if level < 3 {
        &[RoomType::MotorRepair, RoomType::Storage]
    } else if level < 5 {
        &[
            RoomType::MotorRepair,
            RoomType::Storage,
            RoomType::PartsRoom,
        ]
    } else if level < 8 {
        &[
            RoomType::MotorRepair,
            RoomType::Storage,
            RoomType::PartsRoom,
            RoomType::Office,
            RoomType::ElectricalRoom,
        ]
    } else {
        &[
            RoomType::MotorRepair,
            RoomType::Storage,
            RoomType::PartsRoom,
            RoomType::Office,
            RoomType::ElectricalRoom,
            RoomType::BreakRoom,
            RoomType::LoadingBay,
        ]
    };

    choices[rng.range(0, choices.len() as i32) as usize]
}

fn add_enemy_spawn_points(dungeon: &mut Dungeon, rooms: &[Room], level: u32) {
    // Deterministic and simple for now.
    // Keep the player out of the first room and put several potential
    // horde entry points in later rooms/corridors.
    let max_points = (2 + level / 2).min(16) as usize;

    for room in rooms.iter().skip(1).take(max_points) {
        let c = room_center(*room);
        dungeon.enemy_spawn_points.push(c);
    }
}

pub fn generate_dungeon(width: i32, height: i32, level: u32, seed: u64) -> Dungeon {
    // Quality gate: retry sub-attempts until the dungeon has enough rooms
    // and floor space to be playable; fall back to the best seen.
    let mut best: Option<Dungeon> = None;
    let mut best_floor = -1i64;
    for k in 0..6u64 {
        let d = generate_dungeon_inner(width, height, level, seed.wrapping_add(k * 7919));
        let floors = d.tiles.iter().filter(|&&t| t == 1).count() as i64;
        if floors >= 200 && d.rooms.len() >= 3 {
            return d;
        }
        if floors > best_floor {
            best_floor = floors;
            best = Some(d);
        }
    }
    best.unwrap()
}

/// The generator body (original package logic).
fn generate_dungeon_inner(width: i32, height: i32, level: u32, seed: u64) -> Dungeon {
    let mut dungeon = Dungeon::new(width, height);

    let (min_rooms, max_rooms, max_room_size, irregular_chance, extra_connections) =
        level_settings(level);

    let mut rng = SimpleRng::new(mix_seed(seed, level));

    let target_rooms = rng.range(min_rooms, max_rooms + 1);
    let attempts = target_rooms * 90;

    let mut rooms: Vec<Room> = Vec::new();

    for _ in 0..attempts {
        if rooms.len() >= target_rooms as usize {
            break;
        }

        let room_width = rng.range(7, max_room_size + 1);
        let room_height = rng.range(7, max_room_size + 1);

        if room_width >= width - 4 || room_height >= height - 4 {
            continue;
        }

        let x = rng.range(2, width - room_width - 2);
        let y = rng.range(2, height - room_height - 2);

        let shape = if level >= 3 && rng.chance(irregular_chance) {
            if rng.chance(50) {
                RoomShape::LShape
            } else {
                RoomShape::Cross
            }
        } else {
            RoomShape::Rectangle
        };

        let room_type = choose_room_type(rooms.len(), level, &mut rng);

        let room = Room {
            x,
            y,
            width: room_width,
            height: room_height,
            shape,
            room_type,
        };

        if rooms.iter().any(|other| rooms_overlap(room, *other, 1)) {
            continue;
        }

        carve_room(&mut dungeon, room);
        rooms.push(room);
    }

    // Guarantee that a generated level with at least one room has a valid
    // player position.
    if let Some(first) = rooms.first() {
        dungeon.player_start = room_center(*first);
    }

    // Main connected path. Doors are placed at BOTH room centers; the
    // player spawns at the FIRST room's center, so keep that tile FLOOR
    // (convert its door marker back to floor after connections).
    for i in 1..rooms.len() {
        connect_rooms(&mut dungeon, rooms[i - 1], rooms[i], &mut rng);
    }
    // Additional loops on higher levels.
    if rooms.len() > 2 {
        for _ in 0..extra_connections {
            let a = rng.range(0, rooms.len() as i32) as usize;
            let mut b = rng.range(0, rooms.len() as i32) as usize;

            if a == b {
                b = (b + 1) % rooms.len();
            }

            connect_rooms(&mut dungeon, rooms[a], rooms[b], &mut rng);
        }
    }

    // Player spawns at the FIRST room's center: after ALL connections
    // (extra loops can re-door it), guarantee that tile is plain floor.
    if let Some(first) = rooms.first() {
        let c = room_center(*first);
        dungeon.set(c.x, c.y, 1);
    }
    add_enemy_spawn_points(&mut dungeon, &rooms, level);
    dungeon.rooms = rooms;

    dungeon
}

