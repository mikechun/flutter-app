import 'package:flutter/material.dart';
import 'package:tennibot/views/GTCView.dart';

class BrowserPage extends StatefulWidget {
  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  final GlobalKey webViewKey = GlobalKey();

  @override
  void initState() {
    super.initState();
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(children: <Widget>[
      Expanded(
        child: GTCViewComponent(),
      ),
    ]);
  }
}