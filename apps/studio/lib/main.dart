import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/ui/studio_page.dart';

export 'src/api/studio_api_client.dart';
export 'src/editor/flow_editor_controller.dart';
export 'src/sessions/sessions_provider.dart';
export 'src/sessions/submission_models.dart';
export 'src/ui/studio_page.dart';

void main() {
  runApp(
    const ProviderScope(
      child: A2uiStudioApp(),
    ),
  );
}

class A2uiStudioApp extends StatelessWidget {
  const A2uiStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'A2UI Flow Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1D4ED8),
      ),
      home: const StudioPage(),
    );
  }
}
