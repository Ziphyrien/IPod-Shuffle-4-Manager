import 'package:flutter/material.dart';
import 'pages/home_page.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const IPodShuffleManagerApp());
}

class IPodShuffleManagerApp extends StatelessWidget {
  const IPodShuffleManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'iPod Shuffle 4G Manager',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const HomePage(),
    );
  }
}
