import time
import json
from pathlib import Path
import tkinter as tk
import tkinter.messagebox as messagebox
import sys
import importlib
import threading
import requests
from colorama import init, Fore, Style
import concurrent
import concurrent.futures

init(autoreset=True)

# update reminder. do not change this link
GITHUB_REPO = "null138/source-engine-css-enhancer"
CSS_ENHANCER_VERSION = "1.2release"

CONFIG_PATH = Path("css_enhancer_config.json")
MODULE_FOLDER = Path("modules")
LANG_FOLDER = Path("lang")

class GuiConsole(tk.Tk):
	def __init__(self):
		super().__init__()

		self.title("CSS Enhancer Console")
		self.geometry("900x500")
		self.configure(bg="#16181C")  
		
		self.iconbitmap("csench.ico")

		self.text = tk.Text(
			self,
			bg="#2c3038",
			fg="#d0d0d0",
			insertbackground="#ffffff",
			relief="flat",
			font=("Consolas", 11),
			wrap="word"
		)
		self.text.pack(fill="both", expand=True)

		scroll = tk.Scrollbar(self.text, command=self.text.yview)
		self.text.configure(yscrollcommand=scroll.set)
		scroll.pack(side="right", fill="y")

		def on_key(event):
			if (event.state & 0x4) and event.keysym.lower() in ("c", "x", "a"):
				return
			return "break"

		self.text.bind("<Key>", on_key)

		self.text.tag_config("cyan",	foreground="#66f7ff")
		self.text.tag_config("blue",	foreground="#66a3ff")
		self.text.tag_config("magenta", foreground="#ff66f0")
		self.text.tag_config("gray",	foreground="#bfbfbf")
		self.text.tag_config("green",	foreground="#7af77a")
		self.text.tag_config("red",		foreground="#ff6666")

	def write(self, text, tag=None):
		self.after(0, self._write, text, tag)

	def _write(self, text, tag):
		if tag:
			self.text.insert("end", text, tag)
		else:
			self.text.insert("end", text)
		self.text.see("end")

root = GuiConsole()

class GuiStdout:
	def __init__(self, writer):
		self.writer = writer

	def write(self, text):
		if text.strip():
			self.writer.write(text, tag="white")

	def flush(self):
		pass
		
sys.stdout = GuiStdout(root)

def core_print(text: str, error: bool = False):
	prefix = "[CORE] "
	root.write(prefix, "magenta")

	if error:
		root.write(text + "\n", "red")
		return

	template = lang.get("module_loaded", "Loaded module: {name}")
	split_text = template.split("{name}")
	lang_prefix = split_text[0].strip()

	if lang_prefix in text:
		before, after = text.split(lang_prefix, 1)
		root.write(before + lang_prefix + " ", "gray")
		root.write(after.strip() + "\n", "green")
	else:
		root.write(text + "\n", "gray")

def load_config():
	MODULES_CONFIG_PATH = Path("modules/configs")
	MODULES_CONFIG_PATH.mkdir(parents=True, exist_ok=True)
	
	if not CONFIG_PATH.exists():
		config = {
			"game_path": "C:/Counter-Strike Source/cstrike",
			"language": "english",
			"log_clean_interval": 180
		}
		CONFIG_PATH.write_text(json.dumps(config, indent=4), encoding="utf-8")
		return config
	with CONFIG_PATH.open("r", encoding="utf-8") as f:
		return json.load(f)

config = load_config()

def load_language(lang_name):
	lang_file = LANG_FOLDER / f"{lang_name.lower()}.json"
	default_file = LANG_FOLDER / "english.json"
	if lang_file.exists():
		with open(lang_file, "r", encoding="utf-8") as f:
			return json.load(f)
	elif default_file.exists():
		with open(default_file, "r", encoding="utf-8") as f:
			return json.load(f)
	else:
		return {
			"missing_log": "No valid log file path found in css_enhancer_config.json.\n\nPlease set it and restart.",
			"log_not_found": "The log file 'console.log' was not found.\n\nIt has been created automatically.",
			"no_modules": "No modules found in the 'modules' folder.\n\nPlace your .pyd modules inside and restart.",
			"failed_module_load": "Failed to load module: {name}\nError: {error}",
			"core_warning_title": "Core Warning",
			"module_load_error_title": "Module Load Error",
			"module_loaded": "Loaded module: {name}",
			"module_missing_on_new_log": "Module {name} does not have 'on_new_log' function, skipping call.",
			"module_runtime_error": "Module error in {name}: {error}",
			"no_on_new_log_modules": "No modules with 'on_new_log' found, skipping log watcher."
		}

lang = load_language(config.get("language", "english"))

def show_warning_and_exit(message):
	messagebox.showwarning(lang.get("core_warning_title", "Core Warning"), message)
	sys.exit(1)

game_path = Path(config.get("game_path", "C:/Counter-Strike Source/cstrike"))
if not game_path or not game_path.exists():
	show_warning_and_exit(lang["missing_log"])

console_log = game_path / "console.log"
cfg_folder = game_path / "cfg"
css_enhancer_cfg = cfg_folder / "css_enhancer.cfg"
autoexec_cfg = cfg_folder / "autoexec.cfg"

if not console_log.exists():
	console_log.touch()
else:
	console_log.write_text("", encoding="utf-8")

if not cfg_folder.exists():
	cfg_folder.mkdir(parents=True, exist_ok=True)

expected_css_line = "con_logfile console.log"
version_line = f"setinfo css_enhancer {CSS_ENHANCER_VERSION}"

if not css_enhancer_cfg.exists():
	css_enhancer_cfg.write_text(f"{expected_css_line}\n{version_line}\n", encoding="utf-8")
else:
	with css_enhancer_cfg.open("r+", encoding="utf-8") as f:
		lines = [l.strip() for l in f.readlines()]
		if expected_css_line not in lines:
			f.write(f"{expected_css_line}\n")
		if version_line not in lines:
			if lines and not lines[-1]:
				f.write(f"{version_line}\n")
			else:
				f.write(f"\n{version_line}\n")

expected_autoexec_line = "exec css_enhancer.cfg"
if not autoexec_cfg.exists():
	autoexec_cfg.write_text(f"{expected_autoexec_line}\n", encoding="utf-8")
else:
	with autoexec_cfg.open("r+", encoding="utf-8") as f:
		lines = [l.strip() for l in f.readlines()]
		if expected_autoexec_line not in lines:
			f.write(f"{expected_autoexec_line}\n")

loaded_modules = []
modules_with_on_new_log = []

if not MODULE_FOLDER.exists():
	MODULE_FOLDER.mkdir()

sys.path.insert(0, str(MODULE_FOLDER.resolve()))

for f in MODULE_FOLDER.iterdir():
	if f.suffix.lower() == ".pyd":
		module_name = f.stem
		try:
			module = importlib.import_module(module_name)
			loaded_modules.append(module)
			core_print(lang.get("module_loaded", "Loaded module: {name}").format(name=module_name))
			time.sleep(0.05)
			if hasattr(module, "on_new_log"):
				modules_with_on_new_log.append(module)
			if hasattr(module, "set_gui_writer"):
				module.set_gui_writer(root)
		except Exception as e:
			msg = lang["failed_module_load"].format(name=f.name, error=e)
			core_print(msg, error=True)
			messagebox.showwarning(lang.get("module_load_error_title", "Module Load Error"), msg)

if not loaded_modules:
	show_warning_and_exit(lang["no_modules"])

if not modules_with_on_new_log:
	core_print(lang.get("no_on_new_log_modules", "No modules with 'on_new_log' found, skipping log watcher."))

LOG_CLEAN_INTERVAL = config.get("log_clean_interval", 180)
file_lock = threading.Lock()
last_pos = 0

def follow_log(file_path: Path):
	global last_pos
	while True:
		try:
			with file_lock:
				with file_path.open("r", encoding="utf-8", errors="ignore") as f:
					f.seek(last_pos)
					new_lines = f.readlines()
					last_pos = f.tell()
			if new_lines:
				for line in new_lines:
					yield line.rstrip()
			else:
				time.sleep(0.05)
		except Exception as e:
			core_print(f"Log follow error: {e}", error=True)
			time.sleep(1)

def feed_modules(line: str):
	for module in modules_with_on_new_log:
		try:
			module.on_new_log(line.encode("utf-8"), master=root)
		except Exception as e:
			core_print(lang.get("module_runtime_error", "Module error in {name}: {error}").format(
				name=module.__name__, error=e), error=True)

def clean_console_log(file_path: Path):
	global last_pos
	while True:
		time.sleep(LOG_CLEAN_INTERVAL)
		try:
			with file_lock:
				if file_path.exists():
					file_path.write_text("", encoding="utf-8")
					last_pos = 0
		except Exception as e:
			core_print(f"Log clear error: {e}", error=True)

def main_loop():
	for line in follow_log(console_log):
		if line.strip():
			feed_modules(line)

def check_github_version():
	try:
		url = f"https://api.github.com/repos/{GITHUB_REPO}/releases/latest"
		resp = requests.get(url, timeout=5)

		if resp.status_code == 200:
			data = resp.json()
			latest_version = data.get("tag_name", "")

			if latest_version and latest_version != CSS_ENHANCER_VERSION:
				messagebox.showwarning(
					lang.get("update_title", "CSS Enhancer Update"),
					f"{lang.get('update_available', 'A new version is available!')}\n\n"
					f"{lang.get('update_current', 'Current')}: {CSS_ENHANCER_VERSION}\n"
					f"{lang.get('update_latest', 'Latest')}: {latest_version}\n\n"
					f"{lang.get('update_get', 'Get it here')}: {data.get('html_url', '')}"
				)

		else:
			core_print(
				lang.get("update_http_fail", "Could not check latest version. HTTP {code}")
				.format(code=resp.status_code),
				error=True
			)

	except Exception as e:
		core_print(
			lang.get("update_exception", "Version check failed: {error}")
			.format(error=e),
			error=True
		)


if __name__ == "__main__":
	threading.Thread(target=check_github_version, daemon=True).start()
	threading.Thread(target=main_loop, daemon=True).start()
	threading.Thread(target=clean_console_log, args=(console_log,), daemon=True).start()
	root.mainloop()