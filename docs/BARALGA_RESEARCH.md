# Baralga research

Baralga is a Java/Swing time tracker organized into a desktop core and repository API/REST modules. Its baseline feature set is:

- projects; one current activity tracked by a stopwatch; manual activity create, edit, and delete;
- project switching from the system tray and keyboard-oriented entry;
- filtering by project and time interval; reports by day, week, month, quarter, project, and accumulated activity;
- CSV, Excel, iCalendar, and XML export; data import; automatic backups; user settings; and undo/redo;
- local single-user storage, with an optional multi-user server edition.

RTT should carry forward the first four categories, but not Baralga's multi-user model or its Java/Swing implementation. RTT's online mode is personal cross-device sync.

Sources inspected: `README.md`, project architecture graph, `Project`, `ProjectActivity`, `BaralgaDAO`, filter/report/export classes, backup code, and desktop/tray classes in `references/baralga`.
