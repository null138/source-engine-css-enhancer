# [EN]
***[ANY] Server Files***:
- Monitors and logs files downloaded from the server in real time, printing them to the core console.
- Optionally, based on the configuration, the script can automatically clean downloaded files either from the current session when you close the game or perform a full cleanup of all previously downloaded files on the script launch.
<img src="../../serverfiles.png" alt="ServerFiles" width="700">

**Installation:**
- Place the module inside the modules folder.
- Run the core executable and wait for it to create the config file.
- Once the config file is created, any changes to the config file will only take effect after closing and relaunching the core executable.
- Config Options:

   - print_paths ("1") – Prints to the core console whenever new files are downloaded. 1 = On, 0 = Off.

   - log_folders ("maps", "sound", "models", "materials") – Specifies which folders to monitor and clean if auto-clean is enabled.

   - auto_clean_session ("1") – Tracks files downloaded during the current game session and automatically removes them when the game or core executable is closed. 1 = On, 0 = Off.

   - auto_clean_always ("0") – Clears all files that have ever been downloaded from servers when the module starts. 1 = On, 0 = Off.

   - clear_caches ("1") – Removes leftover or incomplete download files on module startup. Recommended to keep enabled as it removes unnecessary files. 1 = On, 0 = Off.

# [RU]
***[ANY] Server Files***:
- Отслеживает и логирует файлы, загружаемые с сервера в реальном времени, выводя их в консоль ядра.
- Опционально, в зависимости от настроек, скрипт может автоматически очищать загруженные файлы: либо только из текущей игровой сессии при закрытии игры, либо выполнять полную очистку всех ранее загруженных файлов при запуске модуля.
<img src="../../serverfiles.png" alt="ServerFiles" width="700">

**Установка:**
- Поместите модуль в папку modules.
- Запустите исполняемый файл ядра и дождитесь создания конфигурационного файла.
- После создания конфигурационного файла любые изменения вступят в силу только после закрытия и повторного запуска ядра.
- Настройки конфигурации:

   - print_paths ("1") – Выводить в консоль ядра информацию о новых загруженных файлах. 1 = Включено, 0 = Выключено.

   - log_folders ("maps", "sound", "models", "materials") – Указывает, какие папки отслеживать и очищать, если включена автоочистка.

   - auto_clean_session ("1") – Отслеживает файлы, загруженные в текущей игровой сессии, и автоматически удаляет их при закрытии игры или ядра. 1 = Включено, 0 = Выключено.

   - auto_clean_always ("0") – Очищает все файлы, когда-либо загруженные с серверов, при запуске модуля. 1 = Включено, 0 = Выключено.

   - clear_caches ("1") – Удаляет остаточные или незавершённые файлы из загрузки при запуске модуля. Рекомендуется оставлять включённым для удаления ненужных файлов. 1 = Включено, 0 = Выключено.
