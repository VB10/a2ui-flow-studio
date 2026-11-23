import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/ui/flow_page.dart';

export 'src/catalog/flow_catalog.dart';
export 'src/catalog/photo_picker.dart';
export 'src/catalog/photo_uploader.dart';
export 'src/session/flow_session_controller.dart';
export 'src/transport/a2ui_transport.dart';
export 'src/transport/http_jsonl_transport.dart';
export 'src/ui/flow_page.dart';

void main() {
  runApp(
    const ProviderScope(
      child: A2uiPlayerApp(),
    ),
  );
}

class A2uiPlayerApp extends StatelessWidget {
  const A2uiPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'A2UI Flow Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2563EB),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
        ),
      ),
      home: const FlowPage(),
    );
  }
}
