import time
import threading
import re
import json
from pathlib import Path
from pypresence import Presence
import a2s	# we could just work with the stock udp library instead of this but uhhhhhh

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
		module_print(f"Core config not found at {core_path}", "red")
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
		module_print(f"Failed to parse core config: {e}", "red")
		return None

core_config = load_core_config()

CLIENT_ID = "1467897633053081600" # do not change this ID. otherwise discord wont be able to update your discord activity
rpc = None
rpc_running = False
rpc_state_lock = threading.Lock()  # just in case
start_time = time.time()

def rpc_thread():
	global rpc, rpc_running
	try:
		rpc = Presence(CLIENT_ID)
		rpc.connect()
		
		module_print(f"\n[DiscordRPC] ", "cyan")
		module_print(f"Connected to Discord", "green")
		
		start_time = time.time()

		with rpc_state_lock:
			if rpc:
				rpc.update(
					details="Counter-Strike: Source",
					state="In Menu",
					start=start_time,
					large_image="csench",
					large_text="CS:S Enhancer",
					small_image="level_icon",
					small_text="Rogue - Level 100",
				)

		while rpc_running:
			time.sleep(1)  # good for idle?

	except Exception as e:
		module_print(f"\n[DiscordRPC] ", "cyan")
		module_print(f"Error: {e}", "red")

def start_rpc():
	time.sleep(2.5)
	global rpc_running
	if rpc_running:
		return
	rpc_running = True
	threading.Thread(target=rpc_thread, daemon=True).start()

CONNECT_PTR = re.compile(r"Connecting to (\d{1,3}(?:\.\d{1,3}){3}:\d+)\.{3}$")

def update_rpc_state(ip_port: str):
	global rpc
	try:
		host, port_str = ip_port.split(":")
		port = int(port_str)
		address = (host, port)
	except Exception as e:
		return

	try:
		info = a2s.info(address, timeout=3.0)
		server_name = getattr(info, "server_name", "Unknown Server")
		map_name = getattr(info, "map_name", "Unknown Map")
		players = getattr(info, "player_count", 0)
		max_players = getattr(info, "max_players", 0)

		details = f"Playing on {server_name}"
		state = f"Map: {map_name} | (Players: {players}/{max_players})"

		with rpc_state_lock:
			if rpc:
				rpc.update(
					details=details,
					state=state,
					start=start_time,
					large_image="csench",
					large_text="CS:S Enhancer",
					small_image="level_icon",
					small_text="Rogue - Level 100",
					buttons=[{"label": "Connect to Server", "url": f"steam://connect/{ip_port}"}]
				)

	except Exception as e:
		module_print(f"\n[DiscordRPC] ", "cyan")
		module_print(f"Error querying server {ip_port}: {e}", "red")


current_server = None
server_update_thread = None
server_update_running = False

def server_update_loop():
	global server_update_running, current_server
	while server_update_running:
		if current_server:
			update_rpc_state(current_server)
		time.sleep(15)

def start_server_updates(ip_port: str):
	global current_server, server_update_thread, server_update_running
	current_server = ip_port
	if not server_update_running:
		server_update_running = True
		server_update_thread = threading.Thread(target=server_update_loop, daemon=True)
		server_update_thread.start()

def on_new_log(line, master=None):
	py_line = line.decode("utf-8", errors="ignore") if isinstance(line, bytes) else str(line)

	match = CONNECT_PTR.search(py_line)
	if match:
		ip_port = match.group(1)
		start_server_updates(ip_port)
		start_time = time.time()
		
		threading.Thread(target=update_rpc_state, args=(ip_port,), daemon=True).start()

threading.Thread(target=start_rpc, daemon=True).start()