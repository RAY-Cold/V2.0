import 'package:flutter/material.dart';
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('About Us')), body: const Padding(padding: EdgeInsets.all(16), child: Text('TourSecure — About Us')));
}
