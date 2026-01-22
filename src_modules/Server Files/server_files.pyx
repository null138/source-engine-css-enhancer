import time
import threading
import json
import re
from pathlib import Path
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
import psutil

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
		module_print(f"\nCore config not found at {core_path}", "red")
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
	except Exception:
		return None

core_config = load_core_config()
GAME_PATH = Path(core_config["game_path"]) if core_config and "game_path" in core_config else Path(".")
DOWNLOADS_ROOT = GAME_PATH / "download"
CORE_PARENT = Path(__file__).parent.parent
BASE_URLS_FILE = CORE_PARENT / "modules" / "Server_Files" / "files.txt"
BASE_URLS_FILE.parent.mkdir(parents=True, exist_ok=True)

def load_monitor_config():
	cfg_path = CORE_PARENT / "modules" / "configs" / "server_files_config.json"

	default_cfg = {
		"print_paths": 1,
		"log_folders": ["maps", "sound", "models", "materials"],
		"auto_clean_session": 0,
		"auto_clean_always": 0,
		"clear_caches": 1
	}

	if not cfg_path.exists():
		try:
			cfg_path.parent.mkdir(parents=True, exist_ok=True)
			with cfg_path.open("w", encoding="utf-8") as f:
				json.dump(default_cfg, f, indent=4)
		except Exception as e:
			module_print(f"\n[Server Files] to create server_files_config.json: {e}", "red")
		return default_cfg

	try:
		with cfg_path.open("r", encoding="utf-8") as f:
			cfg = json.load(f)
			cfg.setdefault("print_paths", 1)
			cfg.setdefault("log_folders", ["maps", "sound", "models", "materials"])
			cfg.setdefault("auto_clean_session", 0)
			cfg.setdefault("auto_clean_always", 0)
			cfg.setdefault("clear_caches", 1)
			return cfg
	except Exception as e:
		module_print(f"\n[Server Files] Failed to load server_files_config.json: {e}", "red")
		return default_cfg

monitor_cfg = load_monitor_config()
WATCH_FOLDERS = set(monitor_cfg.get("log_folders", ["maps", "sound", "models", "materials"]))
PRINT_PATHS = bool(monitor_cfg.get("print_paths", 1))
AUTO_CLEAN_SESSION = bool(monitor_cfg.get("auto_clean_session", 0))
AUTO_CLEAN_ALWAYS = bool(monitor_cfg.get("auto_clean_always", 0))
CLEAR_CACHES = bool(monitor_cfg.get("clear_caches", 1))

for f in WATCH_FOLDERS:
	(DOWNLOADS_ROOT / f).mkdir(parents=True, exist_ok=True)

def log_full_path(path: Path):
	try:
		with BASE_URLS_FILE.open("a", encoding="utf-8") as f:
			f.write(str(path) + "\n")
	except Exception as e:
		module_print(f"\n[Server Files] Failed to write log file: {e}", "red")

def clean_files_from_log():
	if not BASE_URLS_FILE.exists():
		return

	try:
		paths_to_clean = [Path(line.strip()) for line in BASE_URLS_FILE.read_text().splitlines() if line.strip()]
		cleaned_count = 0
		for file_path in paths_to_clean:
			if file_path.exists():
				try:
					file_path.unlink()
					cleaned_count += 1
				except Exception as e:
					module_print(f"\n[Server Files] Failed to remove file: {file_path} | {e}", "red")
		BASE_URLS_FILE.write_text("")
		if cleaned_count > 0:
			module_print(f"\n[Server Files] ", "cyan")
			module_print(f"Cleaned {cleaned_count} file(s)", "green")
	except Exception as e:
		module_print(f"\n[Server Files] Failed to clean files from log: {e}", "red")

def clean_folders_on_startup():
	"""Clean all files in folders specified in WATCH_FOLDERS"""
	cleaned_count = 0
	for folder in WATCH_FOLDERS:
		folder_path = DOWNLOADS_ROOT / folder
		if folder_path.exists():
			for file_path in folder_path.rglob("*"):
				if file_path.is_file():
					try:
						file_path.unlink()
						cleaned_count += 1
					except Exception as e:
						module_print(f"\n[Server Files] Failed to remove file: {file_path} | {e}", "red")
	if cleaned_count > 0:
		if BASE_URLS_FILE.exists():
			BASE_URLS_FILE.write_text("")
		module_print(f"\n[Server Files] ", "cyan")
		module_print(f"Cleaned {cleaned_count} file(s)", "green")

def clear_game_cache():
	"""Remove all files in GAME_PATH/cache"""
	cache_dir = GAME_PATH / "cache"
	if not cache_dir.exists():
		return
	cleaned_count = 0
	for file_path in cache_dir.rglob("*"):
		if file_path.is_file():
			try:
				file_path.unlink()
				cleaned_count += 1
			except Exception as e:
				module_print(f"\n[Server Files] Failed to remove cache file: {file_path} | {e}", "red")
	if cleaned_count > 0:
		module_print(f"\n[Server Files] ", "cyan")
		module_print(f"Cleared {cleaned_count} cache file(s)", "green")

class InstantCreateHandler(FileSystemEventHandler):
	__slots__ = ("_logged_paths",)

	def __init__(self):
		super().__init__()
		self._logged_paths = set()

	def _log(self, path: Path):
		if path.suffix.lower() == ".bz2":
			return

		if path in self._logged_paths:
			return
		self._logged_paths.add(path)

		try:
			rel = path.relative_to(DOWNLOADS_ROOT)
		except ValueError:
			return

		if rel.parts and rel.parts[0] in WATCH_FOLDERS:
			if PRINT_PATHS:
				rel_path_str = str(rel).replace("\\", "/")
				module_print(f"\n[Server Files] ", "cyan")
				module_print(f"Created: ", "green")
				module_print(f"{rel_path_str}", "gray")

			if AUTO_CLEAN_SESSION:
				log_full_path(path)

	def on_created(self, event):
		if not event.is_directory:
			self._log(Path(event.src_path))

	def on_modified(self, event):
		if not event.is_directory:
			self._log(Path(event.src_path))

	def on_moved(self, event):
		if not event.is_directory:
			self._log(Path(event.dest_path))

def is_cstrike_running():
	for proc in psutil.process_iter(["name"]):
		if proc.info["name"] and proc.info["name"].lower() == "cstrike_win64.exe":
			return True
	return False

def monitor_cstrike():
	last_running = False
	while True:
		running = is_cstrike_running()
		if last_running and not running:
			if AUTO_CLEAN_SESSION:            # Well we dont care is there any files or not
				module_print("\n[Server Files] Game closed, cleaning files...", "cyan")
				clean_files_from_log()
				
		last_running = running
		time.sleep(1)

# Uhhh
def run():
	time.sleep(3.0)
	module_print("\n[Server Files] ", "cyan")
	module_print("Monitoring files...\n", "red")

	if CLEAR_CACHES:
		clear_game_cache()

	if AUTO_CLEAN_ALWAYS:
		clean_folders_on_startup()

	elif AUTO_CLEAN_SESSION:
		clean_files_from_log()

	threading.Thread(target=monitor_cstrike, daemon=True).start()

	observer = Observer()
	handler = InstantCreateHandler()
	observer.schedule(handler, str(DOWNLOADS_ROOT), recursive=True)
	observer.start()

	try:
		while True:
			time.sleep(1)
	except KeyboardInterrupt:
		observer.stop()
	observer.join()

threading.Thread(target=run, daemon=True).start()