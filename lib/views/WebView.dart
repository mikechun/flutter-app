import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tennibot/controllers/automator.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';        // Import for Android features.
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';    // Import for iOS features.


Map<String, String> parseCourtSelector(String html) {
  List courtOptions = html
    .split('\n')
    .where((s) => s.contains('>Tennis - Court'))
    .map((s) => s.trim())
    .toList();

  Map<String, String> d = {};
  for (var option in courtOptions) {
    String? key = RegExp(r'.*Court (\d+).*').allMatches(option).first.group(1);
    String? val = RegExp(r'.*value="(\d+)".*').allMatches(option).first.group(1);
    if (key == null || val == null) {
      continue;
    }
    d[key] = val;
  }

  return d;
}


class TimeslotUnavailableException implements Exception {
}

class GTCViewComponent extends StatefulWidget {
  final String initialUrl;

  GTCViewComponent({required this.initialUrl});

  @override
  _GTCViewComponentState createState() => _GTCViewComponentState();

  void reserve(date, time, courtNumber) async {
    await _GTCViewComponentState().run(date, time, courtNumber);
  }
}

class _GTCViewComponentState extends State<GTCViewComponent> {
  late final WebViewController _controller;
  late final WebViewAutomator _automator;

  @override
  void initState() {
    debugPrint('initializing state');
    super.initState();
// #docregion platform_features
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: false,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final WebViewController controller =
        WebViewController.fromPlatformCreationParams(params);
    // #enddocregion platform_features

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            debugPrint('WebView is loading (progress : $progress%)');
          },
          onPageStarted: (String url) {
            debugPrint('Page started loading: $url');
          },
          onPageFinished: (String url) {
            debugPrint('Page finished loading: $url');
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('''
  Page resource error:
    code: ${error.errorCode}
    description: ${error.description}
    errorType: ${error.errorType}
    isForMainFrame: ${error.isForMainFrame}
          ''');
          },
          onNavigationRequest: (NavigationRequest request) {
            if (request.url.startsWith('https://www.youtube.com/')) {
              debugPrint('blocking navigation to ${request.url}');
              return NavigationDecision.prevent;
            }
            debugPrint('allowing navigation to ${request.url}');
            return NavigationDecision.navigate;
          },
          onUrlChange: (UrlChange change) {
            debugPrint('url change to ${change.url}');
          },
        ),
      )
      ..addJavaScriptChannel(
        'Toaster',
        onMessageReceived: (JavaScriptMessage message) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message.message)),
          );
        },
      )
      ..loadRequest(Uri.parse('https://gtc.clubautomation.com'));

    // #docregion platform_features
    if (controller.platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(true);
      (controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }
    // #enddocregion platform_features

    _controller = controller;
    _automator = WebViewAutomator(controller);
    debugPrint('initialized automator');
  }

  login() async {
    await _automator.open(url: 'https://gtc.clubautomation.com');
    await _automator.waitPageload();
    await _automator.type(selector: '#login', value: 'mikechun');
    await _automator.type(selector: '#password', value: 'Tennis4all');
    await _automator.click(selector: '#loginButton');
    await _automator.waitPageload();
  }

  configureSearch() async {
    await _automator.click(selector: '#menu_reserve_a_court');
    await _automator.waitPageload();
  }

  findCourt({required String date, required String interval, String courtNum = '', timeoutSec = 30}) async {
    // 1 is tennis
    await _automator.set(selector: '#location', value: '1');
    // set date
    await _automator.set(selector: '#date', value: date);
    // 90 minutes
    await _automator.check(selector: '#interval-$interval');

    final selectHTML = await _automator.getHTML(selector: '#court');
    final courts = parseCourtSelector(selectHTML);
    // If the court number was not provided, search all
    String courtValue = courts[courtNum] ?? '-1';
    await _automator.set(selector: '#court', value: courtValue);

    return Future.delayed(Duration(seconds: 0), () async {
      while (true) {
        await _automator.click(selector: '#reserve-court-search');
        await _automator.waitElement(selector: '#times-to-reserve > tbody > tr > td:last-child > a, .court-not-available-text');

        debugPrint('finding court...');
        var availabilities = await _automator.find(selector: '#times-to-reserve > tbody > tr > td:last-child > a');
        if (availabilities > 0) {
          return true;
        }
        await Future.delayed(Duration(milliseconds: 250));
      }
    }).timeout(Duration(seconds: timeoutSec));
  }

  reserve(String time) async {
    // await _automator.find(selector: '#times-to-reserve > tbody > tr > td:last-child > a', innerText: time);
    await _automator.click(selector: '#times-to-reserve > tbody > tr > td:last-child > a', innerText: time);
    await _automator.waitElement(selector: '.confirm-reservation-dialog');
    var confirmButtons = await _automator.find(selector: '#confirm');
    if (confirmButtons == 0) {
      throw TimeslotUnavailableException();
    }
    await _automator.click(selector: '#confirm');
    await _automator.waitElement(selector: '.reservation-completed');
    var completionDialogs = await _automator.find(selector: '.reservation-completed');
    if (completionDialogs == 0) {
      throw TimeslotUnavailableException();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.green,
      appBar: AppBar(
        title: const Text('Tennis bot'),
        // This drop down menu demonstrates that Flutter widgets can be shown over the web view.
      ),
      // body: Container(),
      body: WebViewWidget(controller: _controller),
    );
  }

  Future<bool> run(date, time, courtNumber) async {
    // try {
    //   await findCourt(date: date, interval: '90', courtNum: courtNumber);
    // } on TimeoutException {
    //   debugPrint('failed to find court');
    //   return false;
    // }
    await login();

    while (true) {
      await findCourt(date: date, interval: '90', courtNum: courtNumber);

      try {
        await reserve(time);
      } on TimeslotUnavailableException {
        continue;
      }
      // await automator.find(selector: '#times-to-reserve > tbody > tr > td:last-child > a', innerText: '7:30pm');
      // await automator.click(selector: '#times-to-reserve > tbody > tr > td:last-child > a', innerText: '7:30pm');
      // await automator.waitElement(selector: '.confirm-reservation-dialog');
      // var confirmButtons = await automator.find(selector: '#confirm');
      // if (confirmButtons == 0) {
      //   continue;
      // }
      // await automator.click(selector: '#confirm');
      // await automator.waitElement(selector: '.reservation-completed');
      break;
    }
    return true;
  }
}