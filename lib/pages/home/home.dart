import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'package:tennibot/controllers/automator.dart';
import 'package:tennibot/views/DatePicker.dart';
import 'package:tennibot/views/WebView.dart';
import '../../providers/settings_state.dart';

class BrowserPage extends StatefulWidget {
  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  final GlobalKey webViewKey = GlobalKey();

  @override
  void initState() {
    super.initState();

    Future.delayed(Duration(milliseconds: 1000), () async {
      setState(() {
      });
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(children: <Widget>[
      Expanded(
        child: GTCViewComponent(initialUrl: 'google.com'),
      ),
      Container(
        height: 100,
        child: Column(
          children: [
            DatePicker(),
            ElevatedButton(
              onPressed: () {
                // webView.reserve('09/25/2023', '9:30pm', '5');
              },
              child: Text('Reserve')),
          ],
        )

      )
    ]);
  }
}