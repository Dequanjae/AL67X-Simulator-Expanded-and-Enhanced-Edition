mod worldgen;

use godot::prelude::*;
use worldgen::{GenParams, PropDef, Theme};

struct MyExtension;

#[gdextension]
unsafe impl ExtensionLibrary for MyExtension {}

#[derive(GodotClass)]
#[class(base=RefCounted, init)]
struct LevelGeneratorRs {
    base: Base<RefCounted>,
}

#[godot_api]
impl LevelGeneratorRs {
    #[func]
    fn generate(level: i32, theme: Dictionary) -> Dictionary {
        let theme_rs = theme_from_dict(&theme);
        let result = worldgen::generate(level, &theme_rs);

        let mut out = Dictionary::new();
        out.set("ok", result.ok);
        out.set("level", result.level);
        out.set("theme_id", result.theme_id.as_str());
        out.set(
            "arena_size",
            Vector2::new(result.arena_size.0 as f32, result.arena_size.1 as f32),
        );

        let mut props_arr = VariantArray::new();
        for p in &result.props {
            props_arr.push(&prop_to_dict(p).to_variant());
        }
        out.set("props", props_arr);

        let mut walkable = PackedVector3Array::new();
        for (x, y, z) in &result.walkable_points {
            walkable.push(Vector3::new(*x as f32, *y as f32, *z as f32));
        }
        out.set("walkable_points", walkable);

        out.set("reachable_ratio", result.reachable_ratio);
        out.set(
            "player_spawn",
            Vector3::new(
                result.player_spawn.0 as f32,
                result.player_spawn.1 as f32,
                result.player_spawn.2 as f32,
            ),
        );
        out.set("attempts", result.attempts);

        out
    }
}

fn var_f64(d: &Dictionary, key: &str, default: f64) -> f64 {
    d.get(key)
        .and_then(|v| v.try_to::<f64>().ok())
        .unwrap_or(default)
}

fn var_string(d: &Dictionary, key: &str, default: &str) -> String {
    d.get(key)
        .and_then(|v| v.try_to::<GString>().ok())
        .map(|s| s.to_string())
        .unwrap_or_else(|| default.to_string())
}

fn theme_from_dict(theme: &Dictionary) -> Theme {
    let id = var_string(theme, "id", "?");

    let generation = theme
        .get("generation")
        .and_then(|v| v.try_to::<Dictionary>().ok())
        .map(|gen_dict| {
            let arena_size = gen_dict
                .get("arena_size")
                .and_then(|v| v.try_to::<VariantArray>().ok())
                .map(|arr| {
                    let w = arr.get(0).and_then(|v| v.try_to::<f64>().ok()).unwrap_or(40.0);
                    let h = arr.get(1).and_then(|v| v.try_to::<f64>().ok()).unwrap_or(40.0);
                    [w, h]
                })
                .unwrap_or([40.0, 40.0]);
            GenParams {
                arena_size,
                min_clearance: var_f64(&gen_dict, "min_clearance", 3.0),
                spawn_clear_radius: var_f64(&gen_dict, "spawn_clear_radius", 4.5),
                algorithm: var_string(&gen_dict, "algorithm", "scatter"),
                prop_density: var_f64(&gen_dict, "prop_density", 0.03),
            }
        })
        .unwrap_or_default();

    let props = theme
        .get("props")
        .and_then(|v| v.try_to::<VariantArray>().ok())
        .map(|arr| {
            arr.iter_shared()
                .filter_map(|v| v.try_to::<Dictionary>().ok())
                .map(|p| prop_def_from_dict(&p))
                .collect()
        })
        .unwrap_or_default();

    Theme { id, generation, props }
}

fn prop_def_from_dict(d: &Dictionary) -> PropDef {
    let size = d.get("size").and_then(|v| v.try_to::<VariantArray>().ok()).map(|arr| {
        [
            arr.get(0).and_then(|v| v.try_to::<f64>().ok()).unwrap_or(1.0),
            arr.get(1).and_then(|v| v.try_to::<f64>().ok()).unwrap_or(1.0),
            arr.get(2).and_then(|v| v.try_to::<f64>().ok()).unwrap_or(1.0),
        ]
    });
    PropDef {
        shape: d.get("shape").and_then(|v| v.try_to::<GString>().ok()).map(|s| s.to_string()),
        size,
        color: d.get("color").and_then(|v| v.try_to::<GString>().ok()).map(|s| s.to_string()),
        weight: var_f64(d, "weight", 1.0),
        role: var_string(d, "role", ""),
        mesh: d.get("mesh").and_then(|v| v.try_to::<GString>().ok()).map(|s| s.to_string()),
    }
}

fn prop_to_dict(p: &worldgen::Prop) -> Dictionary {
    let mut d = Dictionary::new();
    d.set("shape", p.shape.as_str());
    let mut size_arr = VariantArray::new();
    for s in p.size {
        size_arr.push(&s.to_variant());
    }
    d.set("size", size_arr);
    d.set("color", p.color.as_str());
    let mut pos_arr = VariantArray::new();
    pos_arr.push(&p.pos.0.to_variant());
    pos_arr.push(&p.pos.1.to_variant());
    d.set("pos", pos_arr);
    d.set("rot", p.rot);
    if let Some(mesh) = &p.mesh {
        d.set("mesh", mesh.as_str());
    }
    d
}
