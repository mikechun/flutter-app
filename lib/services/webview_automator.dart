import 'dart:async';
import 'dart:ffi';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';        // Import for Android features.
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';    // Import for iOS features.

class NoElementFoundException implements Exception {}
class WebpageLoadAbortedException implements Exception {}
class WebpageUnopenedException implements Exception {}
class WaitElementAbortedException implements Exception {}

enum WebViewEvents { pageload, waitElement }

class WebViewAutomator {
  late final WebViewController webViewController; 
  late final NavigationDelegate _navigationDelegate;

  static final Finalizer _finalizer = Finalizer((p0) { 
    debugPrint('WebViewAutomator finalizer called');
  });


  WebViewAutomator._create();

  static Future<WebViewAutomator> create() async {
    debugPrint('constructing WebViewAutomator');

    var automator = WebViewAutomator._create();

    _finalizer.attach(automator, 'dead', detach: automator);
    await automator.init();
    return automator;
  }

  Future<void> init() async {
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

    webViewController = WebViewController.fromPlatformCreationParams(params);
    // #enddocregion platform_features
    _navigationDelegate = NavigationDelegate(
        onProgress: (int progress) {
          debugPrint('WebView is loading (progress : $progress%)');
        },
        onPageStarted: (String url) async {
          debugPrint('Page started loading: $url');
        },
        onPageFinished: (String url) async {
          debugPrint('Page finished loading: $url');

          /* JSChannel is not guaranteed to be active before pageFinished.
             PageFinished fires after DOMContentLoaded.  However, we may already
             be in 'load' state.
          */
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
        onNavigationRequest: (NavigationRequest request) async {
          debugPrint('allowing navigation to ${request.url}');
          return NavigationDecision.navigate;
        },
        onUrlChange: (UrlChange change) {
          debugPrint('url change to ${change.url}');
        },
    );

    await webViewController.setNavigationDelegate(_navigationDelegate);
    await webViewController.setJavaScriptMode(JavaScriptMode.unrestricted);
    await webViewController.addJavaScriptChannel(
      '___',
      onMessageReceived: (JavaScriptMessage message) {
        debugPrint(message.message);
      },
    );

    // #docregion platform_features
    if (webViewController.platform is AndroidWebViewController) {
      await AndroidWebViewController.enableDebugging(true);
      await (webViewController.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }
    // #enddocregion platform_features
  }

  String _runJsAnonFunction(List<String> scripts) {
    return [
      "(() => {",
      ...scripts,
      "})();"
    ].join('\n');
  }

  String _getElementsJsScript(selector, innerText) {
    return """
      var els = Array.from(document.querySelectorAll("$selector"));
      if ("$innerText" && els) {
        els = els.filter(el => el.innerText == "$innerText");
      }

      if (!els || !els.length) {
        throw new Error("NoElementFound");
      }
    """;
  }

  Future<void> open({required String url}) async {
    debugPrint('opening');
    await webViewController.loadRequest(Uri.parse(url));
  }

  Future<String> getLocation() async {
    return await webViewController.currentUrl() ?? '';
  }

  Future<String> runJavaScriptOnElements({required String selector, String innerText = '', required String js}) async {
    // Exit early on element not found errors;
    try {
      final r = await webViewController.runJavaScript(
        _runJsAnonFunction([
          _getElementsJsScript(selector, innerText),
        ])
      );
    } on PlatformException catch (e) {
      debugPrint('$selector and innerText $innerText');
      throw NoElementFoundException();
    }

    final r = await webViewController.runJavaScriptReturningResult(
      _runJsAnonFunction([
        _getElementsJsScript(selector, innerText),
        js,
        'return ""',
      ])
    );
    return r.toString();
  }

  Future<bool> type({required String selector, String innerText = '', required String value}) async {
    await runJavaScriptOnElements(
      selector: selector, 
      js: """
        for (var c of "$value") {
          var key = {"key": c};
          for (el of els) {
            el.dispatchEvent(new KeyboardEvent('keydown', key));
            el.dispatchEvent(new KeyboardEvent('input', key));
            el.dispatchEvent(new KeyboardEvent('keyup', key));
            el.value += c;
          }
        }
      """
    );
    return true;
  }
  
  Future<bool> set({required String selector, String innerText = '', required String value}) async {
    String result = await runJavaScriptOnElements(
      selector: selector, 
      js: """
        for (el of els) {
          el.value = "$value";
        }
        return 'true';
        """
    );
    return result == 'true';
  }

  Future<String> getHTML({required String selector}) async {
    debugPrint('gettingHTML: $selector');
    String result = await runJavaScriptOnElements(
      selector: selector, 
      js: """
        // JS Script to get HTML. Returns first item only
        return els[0].outerHTML;
        """
    );
    return result.toString();
  }

  Future<String?> getHTMLorNULL({required String selector}) async {
    try {
      return await getHTML(selector: selector);
    } on NoElementFoundException {
      return null;
    }
  }

  Future<bool> click({required String selector, String innerText = ''}) async {
    String result = await runJavaScriptOnElements(
      selector: selector, 
      innerText: innerText,
      js: """
        els.forEach(el => el.click());
        return true;
        """
    );
    return result == 'true';
  }

  Future<bool> check({required String selector, String innerText = ''}) async {
    String result = await runJavaScriptOnElements(
      selector: selector, 
      js: """
        els.forEach(el => el.checked = true);
        return true;
        """
    );
    return result == 'true';
  }

  Future<void> waitElement({required String listenerSelector, required String targetSelector, String innerText = ''}) async {
    debugPrint('wait element');

    bool timedOut = false;
    await Future.doWhile(() async {
      if (timedOut) { return false; }
      await Future.delayed(Duration(milliseconds: 1));
      try {
        await runJavaScriptOnElements(
          selector: targetSelector, 
          innerText: innerText,
          js: "return true;",
        );
        debugPrint('found element');
        return false;
      } on NoElementFoundException {
        debugPrint('not found element trying again');
        return true;
      }
    }).timeout(Duration(seconds: 10), onTimeout: () {
      timedOut = true;
      throw TimeoutException('Timed out waiting for the page to load');
    });
  }


  Future<void> waitPageLoad() async {
    // Although solution using Completer is cleaner,
    // this solution is at least 30ms faster.
    debugPrint('wait pageload');

    bool timedOut = false;
    return await Future.doWhile(() async {
      if (timedOut) { return false; }

      // JS context is usually delayed.  it may be stuck in previous load state
      Future.delayed(Duration(milliseconds: 1));
      String readyState = await webViewController.runJavaScriptReturningResult('''
        document.readyState;
      ''') as String;
      return readyState == 'complete';
    }).then((_) async {
      await Future.doWhile(() async {
        Future.delayed(Duration(milliseconds: 1));
        String readyState = await webViewController.runJavaScriptReturningResult('''
          document.readyState;
        ''') as String;

        return readyState != 'complete';
      });
    }).timeout(Duration(seconds: 10), onTimeout: () {
      timedOut = true;
      throw TimeoutException('Timed out waiting for the page to load');
    });
  }
}