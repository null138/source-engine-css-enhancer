# css-enhancer-src

**Compile the core into an executable using the following command:**

```
pyinstaller --noconsole --onefile css_enhancer.py ^
--hidden-import=colorsys ^
--hidden-import=tkinter.font ^
--hidden-import=win32gui ^
--hidden-import=win32process ^
--hidden-import=watchdog.observers ^
--hidden-import=watchdog.events ^
--hidden-import=psutil ^
--hidden-import=pydirectinput ^
--hidden-import=a2s ^
--collect-submodules pypresence ^
--add-data "lang;lang" ^
--add-data "csench.ico;." ^
--noupx --icon=csench.ico
```

**Keep the icon file next to the .py to compile** 
