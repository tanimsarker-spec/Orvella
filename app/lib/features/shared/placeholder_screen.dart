import 'package:flutter/material.dart';

/// Clearly labeled stand-in for screens not yet implemented.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Center(
          child: Text(
            '$title: not implemented yet',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
