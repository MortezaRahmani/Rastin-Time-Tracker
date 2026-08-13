import 'package:flutter_test/flutter_test.dart';
import 'package:rastin_time_tracker/formatters.dart';

void main() {
  test('formats elapsed time with leading zeroes', () {
    expect(
      formatDuration(const Duration(hours: 2, minutes: 3, seconds: 4)),
      '02:03:04',
    );
  });

  test('formats total time as HH:MM', () {
    expect(
      formatHoursMinutes(const Duration(hours: 28, minutes: 30)),
      '28:30',
    );
  });
}
