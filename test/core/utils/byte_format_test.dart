import 'package:flutter_test/flutter_test.dart';
import 'package:thaal/core/utils/byte_format.dart';

void main() {
  test('formats sizes in decimal units', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(999), '999 B');
    expect(formatBytes(1024), '1.0 KB');
    expect(formatBytes(3719644), '3.7 MB');
    expect(formatBytes(250000000), '250 MB');
    expect(formatBytes(2000000000000000), '2000 TB');
  });
}
