import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:prism_plurality/core/reset/native_reset_keys.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native key clear refuses while Prism database files remain', (
    tester,
  ) async {
    final dir = await getApplicationDocumentsDirectory();
    await dir.create(recursive: true);
    final db = File(p.join(dir.path, 'prism.db'));
    await db.writeAsString('dummy database residue', flush: true);

    try {
      await const MethodChannelNativeResetKeys().deleteKnownKeys();
      fail('deleteKnownKeys should refuse while prism.db remains on disk');
    } on PlatformException catch (e) {
      expect(
        e.message,
        contains('Refusing to clear Prism secure-storage keys'),
      );
    } finally {
      if (await db.exists()) {
        await db.delete();
      }
    }
  });
}
