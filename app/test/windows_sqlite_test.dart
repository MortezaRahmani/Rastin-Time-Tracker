import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart' as sqlite_open;
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('opens SQLite through the Windows runtime', () {
    if (!Platform.isWindows) return;

    sqlite_open.open.overrideFor(
      sqlite_open.OperatingSystem.windows,
      () => DynamicLibrary.open('winsqlite3.dll'),
    );
    final database = sqlite3.openInMemory();
    expect(database.select('SELECT 1').single.columnAt(0), 1);
    database.dispose();
  });
}
