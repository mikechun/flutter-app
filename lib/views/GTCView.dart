import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tennibot/controllers/automator.dart';
import 'package:tennibot/views/DatePicker.dart';
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
  final String initialUrl = 'https://gtc.clubautomation.com/';

  GTCViewComponent();

  @override
  State<GTCViewComponent> createState() => _GTCViewComponentState();
}

class _GTCViewComponentState extends State<GTCViewComponent> {
  late final WebViewController _controller;
  late final WebViewAutomator _automator;
  DateTime date = DateTime.now().copyWith(hour: 19, minute: 30, second: 0);

  @override
  void initState() {
    debugPrint('initializing GTCView state');
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

    Future.delayed(Duration(seconds: 0), () async {
      await login();
    });
  }

  login() async {
    debugPrint('logging in');
    await _automator.open(url: 'https://gtc.clubautomation.com');
    await _automator.waitPageload();

    final String url = await _automator.getLocation();
    if (url == 'https://gtc.clubautomation.com/member') {
      debugPrint('already logged in');
      return;
    }

    debugPrint('typing');
    await _automator.type(selector: '#login', value: 'mikechun');
    await _automator.type(selector: '#password', value: 'Tennis4all');
    debugPrint('clicking');
    await _automator.click(selector: '#loginButton');
    await _automator.waitPageload();
    debugPrint('logging in success');
  }

  navigateBookingPage() async {
    await _automator.click(selector: '#menu_reserve_a_court');
    await _automator.waitPageload();
  }

  findCourt({required DateTime date, required int duration, int? courtNum, int timeoutSec = 30, int refreshDelayMSec = 1000}) async {
    var formattedDate = '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/${date.year}';

    // tennis location is '1'
    await _automator.set(selector: '#location', value: '1');
    // set date
    await _automator.set(selector: '#date', value: formattedDate);
    // set duration
    await _automator.check(selector: '#interval-$duration');

    final selectHTML = await _automator.getHTML(selector: '#court');
    final courts = parseCourtSelector(selectHTML);
    // If the court number was not provided or not found, search all using -1 value
    String courtValue = '-1';
    if (courtNum is int && courts.containsKey(courtNum.toString())) {
      courtValue = courts[courtNum.toString()] as String;
    } else {
      throw Exception();
    }

    await _automator.set(selector: '#court', value: courtValue);

    return Future.delayed(Duration(seconds: 0), () async {
      while (true) {
        debugPrint('finding court...');
        await _automator.click(selector: '#reserve-court-search');
        await _automator.waitElement(selector: '#times-to-reserve > tbody > tr > td:last-child > a, .court-not-available-text');

        var availabilities = await _automator.find(selector: '#times-to-reserve > tbody > tr > td:last-child > a');
        if (availabilities > 0) {
          return true;
        }
        await Future.delayed(Duration(milliseconds: refreshDelayMSec));
      }
    }).timeout(Duration(seconds: timeoutSec));
  }

  Future<bool> reserve(DateTime date) async {
    final String ampm = date.hour < 12 ? 'am' : 'pm';
    final String hour = date.hour < 13 ? '${date.hour}' : '${date.hour % 12}';
    final String minute = date.minute.toString().padLeft(2, '0');
    final String time = '$hour:$minute$ampm';

    debugPrint(time);
    if (time != 'abc') {
      return false;
    }

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

    await _automator.click(selector: '#button-ok');
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Tennis bot'),
        // This drop down menu demonstrates that Flutter widgets can be shown over the web view.
      ),
      // body: Container(),
      body: Column(
        children: [
          Expanded(child: WebViewWidget(controller: _controller)),
          DatePicker(
            date: date, 
            onChange: (newDate) {
              setState(() {
                date = newDate;
              });
            }
          ),
          ElevatedButton(
            onPressed: () async {
              await run(date, 30, 5);
            },
            child: Text('Reserve')
          ),
        ],
      )
    );
  }

  Future<bool> run(DateTime date, int duration, int courtNumber) async {
    await login();
    await navigateBookingPage();

    while (true) {
      try {
        await findCourt(date: date, duration: duration, courtNum: courtNumber);
      } on TimeoutException {
        return false;
      }

      try {
        await reserve(date);
      } on TimeslotUnavailableException {
        continue;
      }
      break;
    }
    return true;
  }
}