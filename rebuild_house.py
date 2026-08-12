import uuid
import math

def t3d(tx, ty, tz, rx=0, ry=0, rz=0):
    rx, ry, rz = math.radians(rx), math.radians(ry), math.radians(rz)
    cx, sx = math.cos(rx), math.sin(rx)
    cy, sy = math.cos(ry), math.sin(ry)
    cz, sz = math.cos(rz), math.sin(rz)

    m00 = cy * cz + sy * sx * sz
    m01 = -cy * sz + sy * sx * cz
    m02 = sy * cx
    m10 = cx * sz
    m11 = cx * cz
    m12 = -sx
    m20 = -sy * cz + cy * sx * sz
    m21 = sy * sz + cy * sx * cz
    m22 = cy * cx

    return f"Transform3D({m00:g}, {m10:g}, {m20:g}, {m01:g}, {m11:g}, {m21:g}, {m02:g}, {m12:g}, {m22:g}, {tx:g}, {ty:g}, {tz:g})"

class TscnBuilder:
    def __init__(self):
        self.ext_resources = []
        self.sub_resources = []
        self.nodes = []
        self.ext_resources.extend([
            {'type': 'PackedScene', 'path': 'res://player/player.tscn', 'id': '1_player'},
            {'type': 'Script', 'path': 'res://ui/stamina_bar.gd', 'id': '3_03kx2', 'uid': 'uid://ckn40ad61nx2t'},
            {'type': 'Script', 'path': 'res://ui/interaction_prompt.gd', 'id': '4_63pt7', 'uid': 'uid://dugs30clyjof8'},
            {'type': 'PackedScene', 'path': 'res://door/door.tscn', 'id': '4_krg15'}
        ])

        self.add_sub_resource("ProceduralSkyMaterial", "ProceduralSkyMaterial_sky", {})
        self.add_sub_resource("Sky", "Sky_env", {"sky_material": "SubResource(\"ProceduralSkyMaterial_sky\")"})
        self.add_sub_resource("Environment", "Environment_world", {"background_mode": "2", "sky": "SubResource(\"Sky_env\")"})
        self.add_sub_resource("StyleBoxFlat", "StyleBoxFlat_03kx2", {"bg_color": "Color(0.1, 0.1, 0.1, 0.6)"})
        self.add_sub_resource("StyleBoxFlat", "StyleBoxFlat_krg15", {"bg_color": "Color(0.7, 0.8, 0.8, 1)"})

        self.mat_basement = self.add_material("0.4, 0.1, 0.1")   # B2 dark red
        self.mat_garage   = self.add_material("0.35, 0.35, 0.4") # B1 slate
        self.mat_main     = self.add_material("0.1, 0.4, 0.1")   # ground green
        self.mat_back     = self.add_material("0.1, 0.1, 0.4")   # kitchen/rear blue
        self.mat_window   = self.add_material("0.4, 0.4, 0.1")   # window olive
        self.mat_court    = self.add_material("0.3, 0.5, 0.5")   # courtyard teal
        self.mat_upper    = self.add_material("0.5, 0.3, 0.2")   # upper brown
        self.mat_balcony  = self.add_material("0.1, 0.4, 0.4")   # balcony cyan
        self.mat_roof     = self.add_material("0.6, 0.3, 0.1")   # rooftop orange

    def add_sub_resource(self, res_type, res_id, properties):
        self.sub_resources.append({'type': res_type, 'id': res_id, 'properties': properties})
        return res_id

    def add_material(self, color_str):
        res_id = f"StandardMaterial3D_{len(self.sub_resources)}"
        return self.add_sub_resource("StandardMaterial3D", res_id, {"albedo_color": f"Color({color_str}, 1)"})

    def add_box_mesh(self, size, material_id=None):
        res_id = f"BoxMesh_{len(self.sub_resources)}"
        props = {"size": f"Vector3({size[0]}, {size[1]}, {size[2]})"}
        if material_id:
            props["material"] = f"SubResource(\"{material_id}\")"
        return self.add_sub_resource("BoxMesh", res_id, props)

    def add_box_shape(self, size):
        res_id = f"BoxShape3D_{len(self.sub_resources)}"
        return self.add_sub_resource("BoxShape3D", res_id, {"size": f"Vector3({size[0]}, {size[1]}, {size[2]})"})

    def add_node(self, name, node_type, parent=".", properties=None, instance=None):
        node = {'name': name, 'type': node_type, 'parent': parent, 'properties': properties or {}, 'instance': instance}
        self.nodes.append(node)
        return node

    def add_box(self, name, parent, transform, size, material_id=None):
        mesh_id = self.add_box_mesh(size, material_id)
        shape_id = self.add_box_shape(size)
        body_name = name.replace(" ", "_").replace("-", "_")
        self.add_node(body_name, "StaticBody3D", parent, {"transform": transform})
        path = f"{parent}/{body_name}" if parent != "." else body_name
        self.add_node("Mesh", "MeshInstance3D", path, {"mesh": f"SubResource(\"{mesh_id}\")"})
        self.add_node("Collision", "CollisionShape3D", path, {"shape": f"SubResource(\"{shape_id}\")"})

    def add_door_centered(self, name, parent, cx, cy, cz, ry, open_angle=90, interaction_range=2.5, direction=1):
        rx_rad = math.radians(ry)
        tx = cx - 0.6 * math.cos(rx_rad)
        tz = cz + 0.6 * math.sin(rx_rad)
        door_name = name.replace(" ", "_").replace("-", "_")
        self.add_node(door_name, "Node3D", parent, {
            "transform": t3d(tx, cy, tz, 0, ry, 0),
            "open_angle": f"{open_angle}.0",
            "interaction_range": f"{interaction_range}",
            "hinge_direction": f"{direction}"
        }, instance="4_krg15")

    def generate(self):
        lines = []
        lines.append(f'[gd_scene format=3 uid="uid://{uuid.uuid4().hex[:12]}"]')
        lines.append('')
        for res in self.ext_resources:
            uid_str = f' uid=\"{res["uid"]}\"' if 'uid' in res else ''
            lines.append(f'[ext_resource type=\"{res["type"]}\" path=\"{res["path"]}\" id=\"{res["id"]}\"{uid_str}]')
        lines.append('')
        for res in self.sub_resources:
            lines.append(f'[sub_resource type=\"{res["type"]}\" id=\"{res["id"]}\"]')
            for k, v in res['properties'].items():
                lines.append(f'{k} = {v}')
            lines.append('')
        for node in self.nodes:
            parent_str = f' parent=\"{node["parent"]}\"' if node["parent"] else ''
            inst_str = f' instance=ExtResource(\"{node["instance"]}\")' if node["instance"] else ''
            lines.append(f'[node name=\"{node["name"]}\" type=\"{node["type"]}\"{parent_str}{inst_str}]')
            for k, v in node['properties'].items():
                if isinstance(v, str) and '\n' in v:
                     lines.append(f'{k} = \"{v}\"')
                else:
                    lines.append(f'{k} = {v}')
            lines.append('')
        return '\n'.join(lines)

b = TscnBuilder()
b.add_node("TestEnvironment", "Node3D", parent="")
b.add_node("WorldEnvironment", "WorldEnvironment", parent=".", properties={"environment": "SubResource(\"Environment_world\")"})
b.add_node("DirectionalLight3D", "DirectionalLight3D", parent=".", properties={
    "transform": "Transform3D(0.866025, -0.25, 0.433013, 0, 0.866025, 0.5, -0.5, -0.433013, 0.75, 0, 10, 0)",
    "shadow_enabled": "true"
})

def wall_piece(name, x, y, z, sx, sy, sz, mat=None):
    b.add_box(name, ".", t3d(x, y, z), (sx, sy, sz), mat)

def wall_with_hole(name, y_base, x_pos, z_pos, length, thickness, hole_pos, hole_w, hole_h, is_x, mat=None, wall_h=3.0):
    hw = hole_w / 2.0
    hl = length / 2.0
    ll = (hole_pos - hw) - (-hl)
    if ll > 0:
        lx = x_pos + (-hl + ll/2.0) if is_x else x_pos
        lz = z_pos + (-hl + ll/2.0) if not is_x else z_pos
        wall_piece(f"{name}_L", lx, y_base + wall_h/2.0, lz, ll if is_x else thickness, wall_h, thickness if is_x else ll, mat)
    rl = hl - (hole_pos + hw)
    if rl > 0:
        rx = x_pos + (hl - rl/2.0) if is_x else x_pos
        rz = z_pos + (hl - rl/2.0) if not is_x else z_pos
        wall_piece(f"{name}_R", rx, y_base + wall_h/2.0, rz, rl if is_x else thickness, wall_h, thickness if is_x else rl, mat)
    th = wall_h - hole_h
    if th > 0:
        tx = x_pos + hole_pos if is_x else x_pos
        tz = z_pos + hole_pos if not is_x else z_pos
        wall_piece(f"{name}_T", tx, y_base + hole_h + th/2.0, tz, hole_w if is_x else thickness, th, thickness if is_x else hole_w, mat)


# ============================================================
# OLD VIETNAMESE TUBE HOUSE ("nha ong") - graybox layout
#
#   X: -3.5 (west) .. 3.5 (east)      7m narrow frontage
#   Z: -10 (front/gate) .. 9 (rear)   19m deep
#   Y: B2=-6  B1=-3  Ground=0  Upper=3  Rooftop=6   (3m/level)
#
#   Corridor spine: X -3.5..-1   Room strip: X -1..3.5
#   Every vertical ramp has exactly ONE floor-hole, in the floor
#   of the level it rises INTO (the level it starts from stays solid).
# ============================================================

def floor_slab(name, x0, x1, y, z0, z1, mat=None):
    wall_piece(name, (x0+x1)/2.0, y - 0.1, (z0+z1)/2.0, x1-x0, 0.2, z1-z0, mat)

def partition(name, x_pos, z_pos, length, is_x, y_base=0.0, hole=None, mat=None, thickness=0.2, wall_h=3.0):
    if hole is None:
        if is_x:
            wall_piece(name, x_pos, y_base + wall_h/2.0, z_pos, length, wall_h, thickness, mat)
        else:
            wall_piece(name, x_pos, y_base + wall_h/2.0, z_pos, thickness, wall_h, length, mat)
    else:
        hole_pos, hole_w, hole_h = hole
        wall_with_hole(name, y_base, x_pos, z_pos, length, thickness, hole_pos, hole_w, hole_h, is_x, mat, wall_h)

def add_ramp(name, x, z, y_bottom, rise, axis, run=3.0, width=2.5):
    length = math.hypot(rise, run)
    angle = math.degrees(math.atan2(rise, run))
    cy = y_bottom + rise / 2.0
    if axis == 'z':
        b.add_box(name, ".", t3d(x, cy, z, angle, 0, 0), (width, 0.2, length))
    else:
        b.add_box(name, ".", t3d(x, cy, z, 0, 0, -angle), (length, 0.2, width))

WEST, EAST = -3.5, 3.5
CX = -1.0          # corridor(-strip) / room(-strip) boundary
CORR_MID = -2.25
Z_FRONT, Z_HALL, Z_LIVING, Z_COURT, Z_ALTAR, Z_DINING, Z_REAR = -10.0, -7.0, -3.0, 0.0, 3.0, 6.0, 9.0
