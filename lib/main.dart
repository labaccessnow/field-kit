import 'package:flutter/material.dart';

import 'src/shell.dart';
import 'src/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FieldKitApp());
}

class FieldKitApp extends StatelessWidget {
  const FieldKitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Field Kit',
      debugShowCheckedModeBanner: false,
      theme: fieldKitTheme(),
      home: const Shell(),
    );
  }
}
