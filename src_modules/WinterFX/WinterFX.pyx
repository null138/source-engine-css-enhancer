import os
import re
import gc
import json
import struct
import math
import time
import threading
import shutil
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import lzma
import zlib

gui_writer = None

def set_gui_writer(writer):
	global gui_writer
	gui_writer = writer

def module_print(text, color="white"):
	if gui_writer:
		gui_writer.write(text, tag=color)
	else:
		print(text)

def load_core_config():
	core_path = Path(__file__).parent.parent / "css_enhancer_config.json"
	if not core_path.exists():
		module_print(f"Core config not found at {core_path}")
		return None
	with core_path.open("r", encoding="utf-8") as f:
		lines = f.readlines()
	clean_lines = []
	for line in lines:
		line_no_comment = re.split(r'(?<!:)//', line)[0].rstrip()
		if line_no_comment:
			clean_lines.append(line_no_comment)
	try:
		return json.loads("\n".join(clean_lines))
	except Exception as e:
		return None

core_config = load_core_config()
if core_config and "game_path" in core_config:
	GAME_PATH = Path(core_config["game_path"])
else:
	GAME_PATH = Path(".")

def load_winterfx_config():
	cfg_path = Path(__file__).parent / "configs" / "winterfx_config.json"

	if not cfg_path.exists():
		default_cfg = {"maps": ["de_", "cs_"]}
		try:
			with cfg_path.open("w", encoding="utf-8") as f:
				json.dump(default_cfg, f, indent=4)
		except Exception as e:
			module_print(f"Failed to create winterfx_config.json: {e}")
		return default_cfg

	try:
		with cfg_path.open("r", encoding="utf-8") as f:
			return json.load(f)
	except Exception as e:
		return {"maps": ["de_", "cs_"]}

winterfx_config = load_winterfx_config()

map_prefixes = []
if "maps" in winterfx_config and isinstance(winterfx_config["maps"], list):
	map_prefixes = [p.lower() for p in winterfx_config["maps"]]

filter_all = "all" in map_prefixes
CUSTOM_TEXTURE = "css_enhancer/snowfloor"

def install_snowfloor_vtf():
	time.sleep(0.5) # temp solution. we need to load the modules in order instead of loading everything at once
	source_vtf = Path(__file__).parent / "WinterFX" / "snowfloor.vtf"
	target_dir = GAME_PATH / "materials" / "css_enhancer"
	target_vtf = target_dir / "snowfloor.vtf"

	try:
		if not source_vtf.exists():
			module_print(f"Missing texture snowfloor.vtf at: {source_vtf}", "red")
			return

		target_dir.mkdir(parents=True, exist_ok=True)

		if not target_vtf.exists() or source_vtf.stat().st_mtime > target_vtf.stat().st_mtime:
			shutil.copy2(source_vtf, target_vtf)

	except Exception as e:
		module_print(f"Failed to copy snowfloor.vtf: {e}", "red")

install_snowfloor_vtf()

MAX_WORKERS = 5
OUTPUT_DIR = GAME_PATH / "custom" / "WinterFX"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

download_maps_folder = GAME_PATH / "download" / "maps"
maps_folder = GAME_PATH / "maps"

bsp_paths = []
if download_maps_folder.exists():
	bsp_paths.extend(download_maps_folder.rglob("*.bsp"))
if maps_folder.exists():
	bsp_paths.extend(maps_folder.rglob("*.bsp"))

bsp_paths = list(set(bsp_paths))

if not filter_all and map_prefixes:
	bsp_paths = [
		p for p in bsp_paths
		if any(p.stem.lower().startswith(prefix) for prefix in map_prefixes)
	]

CORE_PARENT = Path(__file__).parent.parent
MAPS_TXT_PATH = CORE_PARENT / "modules" / "WinterFX" / "maps.txt"

if OUTPUT_DIR.exists():
	if not MAPS_TXT_PATH.exists() or MAPS_TXT_PATH.stat().st_size == 0:
		shutil.rmtree(OUTPUT_DIR)

MAPS_TXT_PATH.parent.mkdir(parents=True, exist_ok=True)

processed_maps = set()
if MAPS_TXT_PATH.exists():
	with open(MAPS_TXT_PATH, "r", encoding="utf-8") as f:
		for line in f:
			line = line.strip()
			if line:
				processed_maps.add(line.lower())

bsp_paths = [p for p in bsp_paths if p.stem.lower() not in processed_maps]

IGNORED_ROOTS = {"sprite","sprites","props","prop","sound","sounds","models","particle","particles"}

def is_ignored_texture(texname):
	if not texname or '/' not in texname:
		return False
	root = texname.split('/')[0].lower()
	return root in IGNORED_ROOTS

def sanitize_path_component(name):
	name = name.strip()
	name = re.sub(r'[<>:"\\|?*]', '_', name)
	name = re.sub(r'\s+', '_', name)
	return name

def create_vmt(texture_path, custom_texture):
	parts = texture_path.split('/')
	sanitized_parts = [sanitize_path_component(p) for p in parts]
	vmt_path = OUTPUT_DIR / "materials" / Path(*sanitized_parts).with_suffix(".vmt")
	if vmt_path.exists():
		return False
	vmt_path.parent.mkdir(parents=True, exist_ok=True)
	vmt_content = f"""
"LightmappedGeneric"
{{
	"$basetexture" "{custom_texture}"
	"$surfaceprop" "snow"
	"$color" "[0.515 0.515 0.515]"
}}
""".strip()
	with open(vmt_path, "w") as f:
		f.write(vmt_content)
	return True

def read_struct(f, fmt):
	size = struct.calcsize(fmt)
	data = f.read(size)
	if len(data) != size:
		raise EOFError("File data size mismatch")
	return struct.unpack(fmt, data)

def normalize(v):
	length = math.sqrt(v[0]**2 + v[1]**2 + v[2]**2)
	if length == 0:
		return (0.0,0.0,0.0)
	return (v[0]/length, v[1]/length, v[2]/length)

def decompress_bsp_lump(raw: bytes, uncompressed_size: int) -> bytes:
	if len(raw) < 13:
		return raw
	magic, actual_size, lzma_size = struct.unpack("<III", raw[:12])
	LZMA_ID = (ord('A') << 24) | (ord('M') << 16) | (ord('Z') << 8) | ord('L')
	if magic != LZMA_ID:
		try:
			return zlib.decompress(raw)
		except Exception:
			return raw
	props = raw[12:17]
	comp_data = raw[17:17+lzma_size]
	header = props + struct.pack("<Q", actual_size)
	try:
		return lzma.decompress(header + comp_data)
	except lzma.LZMAError:
		return raw

def read_and_decompress_lump(f, lumps, index):
	ofs, length, lump_version, fourcc = lumps[index]
	f.seek(ofs)
	raw = f.read(length)
	if fourcc > 0:
		return decompress_bsp_lump(raw, fourcc)
	else:
		return raw

def process_bsp(bsp_path):
	bsp_name = bsp_path.stem
	textures_to_create = set()

	try:
		with open(bsp_path, "rb") as f:
			ident, version = read_struct(f, "<II")
			if ident != 0x50534256:
				return 0

			lumps = [read_struct(f, "<IIII") for _ in range(64)]

			LUMP_PLANES = 1
			LUMP_TEXDATA = 2
			LUMP_VERTEXES = 3
			LUMP_FACES = 7
			LUMP_TEXINFO = 6
			LUMP_TEXDATA_STRING_TABLE = 44
			LUMP_TEXDATA_STRING_DATA = 43

			planes_data = read_and_decompress_lump(f, lumps, LUMP_PLANES)
			planes = [struct.unpack("<fff f I", planes_data[i:i+20])[:4] for i in range(0, len(planes_data), 20) if i+20 <= len(planes_data)]

			td_data = read_and_decompress_lump(f, lumps, LUMP_TEXDATA)
			texdata = [struct.unpack("<3f5i", td_data[i:i+32])[3] for i in range(0, len(td_data), 32) if i+32 <= len(td_data)]

			ti_data = read_and_decompress_lump(f, lumps, LUMP_TEXINFO)
			texinfos = [struct.unpack("<8f8fII", ti_data[i:i+72])[17] for i in range(0, len(ti_data), 72) if i+72 <= len(ti_data)]

			st_data = read_and_decompress_lump(f, lumps, LUMP_TEXDATA_STRING_TABLE)
			string_table = [struct.unpack("<I", st_data[i:i+4])[0] for i in range(0, len(st_data), 4) if i+4 <= len(st_data)]
			sd_data = read_and_decompress_lump(f, lumps, LUMP_TEXDATA_STRING_DATA)

			def get_texture_name(index):
				if index < 0 or index >= len(string_table):
					return None
				pos = string_table[index]
				if pos >= len(sd_data):
					return None
				end = sd_data.find(b"\x00", pos)
				if end == -1:
					end = len(sd_data)
				return sd_data[pos:end].decode("utf-8", errors="ignore")

			face_data = read_and_decompress_lump(f, lumps, LUMP_FACES)
			faces = []
			for i in range(0, len(face_data), 56):
				if i+56 > len(face_data):
					break
				data = face_data[i:i+56]
				planenum, side, _, firstedge = struct.unpack("<HBBi", data[:8])
				numedges, texinfo_index, dispinfo, fogid = struct.unpack("<hhhh", data[8:16])
				lightofs, area = struct.unpack("<if", data[24:32])
				faces.append({
					"planenum": planenum,
					"side": side,
					"texinfo_index": texinfo_index,
					"area": area
				})

			texture_dirs = {}
			for face in faces:
				planenum = face["planenum"]
				if 0 <= planenum < len(planes):
					nx, ny, nz = normalize(planes[planenum][:3])
				else:
					nx, ny, nz = 0.0, 0.0, 0.0

				texinfo_index = face["texinfo_index"]
				if texinfo_index < 0 or texinfo_index >= len(texinfos):
					continue
				texdata_index = texinfos[texinfo_index]
				if texdata_index < 0 or texdata_index >= len(texdata):
					continue
				texname = get_texture_name(texdata[texdata_index])
				if not texname or texname.strip() == "" or texname.lower().startswith("tools/") or is_ignored_texture(texname):
					continue

				dir = "up" if nz > 0.5 else "down" if nz < 0.5 else "horizontal"
				if texname not in texture_dirs:
					texture_dirs[texname] = set()
				texture_dirs[texname].add(dir)

			for texname, dirs in texture_dirs.items():
				if dirs == {"up"}:
					textures_to_create.add(texname)

	except Exception as e:
		return 0

	created_count = 0
	for tex in textures_to_create:
		if create_vmt(tex, CUSTOM_TEXTURE):
			created_count += 1

	return created_count

def run():
	global bsp_paths
	time.sleep(1.0) # temp solution. we need to load the modules in order instead of loading everything at once
	module_print("\n[WinterFX] ", "cyan")
	module_print("Processing maps...\n", "red")

	total_textures = 0
	total_maps = len(bsp_paths)

	futures = []
	with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
		for bsp_path in bsp_paths:
			futures.append(executor.submit(process_bsp, bsp_path))
		for future in as_completed(futures):
			total_textures += future.result()

	with open(MAPS_TXT_PATH, "a", encoding="utf-8") as f:
		for bsp_path in bsp_paths:
			f.write(bsp_path.stem + "\n")

	module_print("\n[WinterFX] ", "cyan")
	module_print(f"Created {total_textures} snow textures for {total_maps} maps.\n", "green")

	del bsp_paths
	del futures
	gc.collect()

threading.Thread(target=run, daemon=True).start()