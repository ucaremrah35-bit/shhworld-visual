import 'package:flutter/material.dart';
import 'noise_map_page.dart';

void main() {
  runApp(const ShhWorldApp());
}

class ShhWorldApp extends StatefulWidget {
  const ShhWorldApp({super.key});
  @override
  State<ShhWorldApp> createState() => _ShhWorldAppState();
}

class _ShhWorldAppState extends State<ShhWorldApp> {
  ThemeMode _mode = ThemeMode.light;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShhWorld — Gürültü Haritası',
      debugShowCheckedModeBanner: false,
      themeMode: _mode,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      home: NoiseMapPage(
        onToggleTheme: () {
          setState(() {
            _mode = _mode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
          });
        },
      ),
    );
  }
}
