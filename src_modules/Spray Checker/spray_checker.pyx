import os
import struct
import json
import re
import time
import threading
from pathlib import Path
from colorama import init, Fore, Style
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
import shutil
from datetime import datetime

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

USER_CUSTOM_DIR = GAME_PATH / "download" / "user_custom"
USER_CUSTOM_DIR.mkdir(exist_ok=True, parents=True)

MALFORMED_DIR = USER_CUSTOM_DIR / "malformed_sprays"
MALFORMED_DIR.mkdir(exist_ok=True, parents=True)

init(convert=True)
CYAN = "cyan"
GRAY = "gray"
BLUE = "blue"
GREEN = "green"
RED = "red"

g_iVal = [
	86, 84, 70, 0, 7, 0, 0, 0, 42, 0, 0, 0,
	42, 0, 0, 0, 42, 42, 42, 42, 42, 42, 42, 42,
	42, 42, 42, 0, 0, 0, 0, 0, 0, 0, 0, 0
]

# excess list of formats. some are redundant or may be incorrect?
FORMAT_INFO = {
	"A8": {"bpp": 8, "compressed": False},
	"ABGR8888": {"bpp": 32, "compressed": False},
	"ARGB8888": {"bpp": 32, "compressed": False},
	"BGR565": {"bpp": 16, "compressed": False},
	"BGR888": {"bpp": 24, "compressed": False},
	"BGRA4444": {"bpp": 16, "compressed": False},
	"BGRA5551": {"bpp": 16, "compressed": False},
	"BGRA8888": {"bpp": 32, "compressed": False},
	"BGRX8888": {"bpp": 32, "compressed": False},
	"DXT1": {"block_bytes": 8, "compressed": True},
	"DXT1_ONEBITALPHA": {"block_bytes": 8, "compressed": True},
	"DXT3": {"block_bytes": 16, "compressed": True},
	"DXT5": {"block_bytes": 16, "compressed": True},
	"I8": {"bpp": 8, "compressed": False},
	"IA88": {"bpp": 16, "compressed": False},
	"P8": {"bpp": 8, "compressed": False},
	"RGB565": {"bpp": 16, "compressed": False},
	"RGB888": {"bpp": 24, "compressed": False},
	"RGBA8888": {"bpp": 32, "compressed": False},
	"RGBA16161616": {"bpp": 64, "compressed": False},
	"RGBA16161616F": {"bpp": 64, "compressed": False},
	"UV88": {"bpp": 16, "compressed": False},
	"UVLX8888": {"bpp": 32, "compressed": False},
	"UVWQ8888": {"bpp": 32, "compressed": False},
}

def val_file(header_bytes):
	iRead = list(header_bytes)
	if len(iRead) > 35 and iRead[0:4] == [82, 73, 70, 70] and iRead[8:12] == [87, 65, 86, 69]:
		if iRead[34] + iRead[35]*256 == 32:
			return 34, iRead[34]
		return -1, "Invalid header length"

	if len(iRead) > 25 and (iRead[24] | (iRead[25]<<8)) > 66:
		return 24, (iRead[24] | (iRead[25]<<8))

	for i in range(min(len(g_iVal), len(iRead))):
		read_ok = True
		if g_iVal[i] == 42:
			if i == 8:
				read_ok = iRead[i] <= 5
			elif i in (16, 18) and i+1 < len(iRead):
				n = iRead[i+1]*256 + iRead[i]
				read_ok = 0 <= n <= 8192
			elif i == 20 and i+3 < len(iRead):
				n = (iRead[i+3]<<24)|(iRead[i+2]<<16)|(iRead[i+1]<<8)|iRead[i]
				read_ok = not (n & (0x8000|0x10000|0x80000|0x800000))
		elif i < 27 and iRead[i] != g_iVal[i]:
			read_ok = False
		if not read_ok:
			if i == 20 and i+3 < len(iRead):
				combined = (iRead[20] | (iRead[21]<<8) | (iRead[22]<<16) | (iRead[23]<<24))
				return i, combined
			else:
				return i, iRead[i]
	return -1, "No match found"

class VTFHeader:
	def __init__(self, data):
		if len(data) < 80 or data[:4] != b'VTF\x00':
			raise ValueError("Not a VTF file")
		self.version_major, self.version_minor = struct.unpack('<II', data[4:12])
		self.width, self.height = struct.unpack('<HH', data[16:20])
		self.frames = struct.unpack('<H', data[24:26])[0]
		self.num_mip_levels = data[56]
		self.highres_format_id = struct.unpack('<I', data[52:56])[0]
		self.lowres_format_id = data[57]
		self.lowres_width = data[61]
		self.lowres_height = data[62]
		self.highres_format_name = self.map_format_id(self.highres_format_id)
		self.lowres_format_name = self.map_format_id(self.lowres_format_id)

	def map_format_id(self, fmt_id):
		return {
			0: "RGBA8888", 1: "ABGR8888", 2: "RGB888", 3: "BGR888",
			4: "RGB565", 5: "I8", 6: "IA88", 7: "DXT1", 9: "DXT5",
			12: "BGRA8888", 13: "DXT1", 14: "DXT3", 15: "DXT5", 16: "BGRX8888"
		}.get(fmt_id, "RGBA8888")

class CVTFTexture:
	def __init__(self, filepath):
		self.filepath = Path(filepath)
		with open(filepath, 'rb') as f:
			self.header = VTFHeader(f.read(80))
		self.m_nMipCount = self.header.num_mip_levels

	def compute_face_size(self, width, height, mip_count, format_name):
		info = FORMAT_INFO[format_name]
		size = 0
		for mip in range(mip_count):
			w, h = max(1, width >> mip), max(1, height >> mip)
			if info["compressed"]:
				blocks_w = (w + 3)//4
				blocks_h = (h + 3)//4
				size += blocks_w * blocks_h * info["block_bytes"]
			else:
				size += w * h * info["bpp"]//8
		return size

	def calculate_file_size(self):
		frames_count = max(1, self.header.frames)
		highres = self.compute_face_size(
			self.header.width, self.header.height, self.m_nMipCount, self.header.highres_format_name
		) * frames_count
		thumb = self.compute_face_size(
			self.header.lowres_width, self.header.lowres_height, 1, self.header.lowres_format_name
		)
		return highres + thumb

def handle_detected_file(file_path: Path, reason: str, protected=False):
	try:
		try:
			rel_path = file_path.relative_to(USER_CUSTOM_DIR)
		except ValueError:
			rel_path = file_path.name
	
		suffix_text = "Protected" if protected else "Deleted"
		suffix_color = "green"
	
		target_path = MALFORMED_DIR / file_path.name
		if file_path.exists():
			shutil.move(str(file_path), target_path)

		with open(file_path, "w", encoding="utf-8") as f:
			f.write(f"@ {reason} | {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
	
		rel_path_str = str(rel_path).replace("\\", "/")

		module_print("\n[Crashing Spray] ", "cyan")
		module_print(f"user_custom/{rel_path_str} | ", "gray")
		module_print(f"{reason}. ", "blue")
		module_print(f"{suffix_text}", suffix_color)

	except Exception as e:
		module_print(f"Failed to move file: {file_path} -> {e}", "red")

def wait_file_ready(file_path, retries=10, delay=0.1):
	file_path = Path(file_path)
	last_size = -1
	for _ in range(retries):
		if not file_path.exists():
			return False
		size = file_path.stat().st_size
		if size == last_size and size > 0:
			return True
		last_size = size
		time.sleep(delay)
	return False

def scan_file(file_path: Path):
	if MALFORMED_DIR.resolve() in [p.resolve() for p in file_path.parents]:
		return

	try:
		with open(file_path, "rb") as f:
			first_byte = f.read(1)
			if first_byte == b"@":
				return
	except Exception:
		return

	try:
		with open(file_path, "rb") as f:
			header = f.read(256)

		idx, val = val_file(header)
		if idx != -1:
			handle_detected_file(file_path, f"Header: {idx}, value: {val}", protected=True)
			return

		try:
			v = CVTFTexture(file_path)
			if v.header.version_major != 7 or v.header.version_minor not in range(7):
				handle_detected_file(file_path, f"VTF file version invalid: {v.header.version_major}.{v.header.version_minor}")
				return

			calc_size = v.calculate_file_size()
			actual_size = file_path.stat().st_size
			diff = abs(calc_size - actual_size) / max(calc_size, actual_size)

			if diff > 0.05 and (calc_size >= 5*1024 or actual_size >= 5*1024):
				handle_detected_file(file_path,
									 f"Size mismatch: actual: {actual_size}, calculated: {calc_size}",
									 protected=True)
				return

		except Exception:
			handle_detected_file(file_path, "File is malformed or not a VTF")

	except Exception as e:
		module_print(f"Error processing vtf {file_path}: {e}")

def scan_combined(folder_path=USER_CUSTOM_DIR):
	for root, _, files in os.walk(folder_path):
		for file in files:
			scan_file(Path(root) / file)
	module_print("\n[Crashing Spray] ", "cyan")
	module_print("Scan complete. Running real time checker...\n", "green")

class VTFHandler(FileSystemEventHandler):
	def on_created(self, event):
		if not event.is_directory and wait_file_ready(event.src_path):
			scan_file(Path(event.src_path))

	def on_modified(self, event):
		if not event.is_directory and wait_file_ready(event.src_path):
			scan_file(Path(event.src_path))

def run():
	time.sleep(3.0)
	module_print("\n[Crashing Spray] ", "cyan")
	module_print("Starting the folder scan...\n", "red")

	scan_combined()
	
	observer = Observer()
	observer.schedule(VTFHandler(), str(USER_CUSTOM_DIR), recursive=True)
	observer.start()
	try:
		while True:
			time.sleep(1)
	except KeyboardInterrupt:
		observer.stop()
	observer.join()

threading.Thread(target=run, daemon=True).start()