import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/thinking/home_screen.dart';

void main() {
  runApp(const ProviderScope(child: ThinkOutLoudApp()));
}

class ThinkOutLoudApp extends StatelessWidget {
  const ThinkOutLoudApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Think Out Loud',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const HomeScreen(),
    );
  }
}
