import 'package:flutter/material.dart';
import 'views/chat_screen.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quds WhatsApp Clone',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00a884),
          primary: const Color(0xFF008069),
          secondary: const Color(0xFF00a884),
        ),
        useMaterial3: true,
        fontFamily: 'Inter',
      ),
      home: const ChatScreen(),
    );
  }
}
