import 'dart:async';

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
  final Map<WebViewEvents, Completer> promises = {};
  late final WebViewController webViewController; 
  late final NavigationDelegate _navigationDelegate;
  final Completer aaCompleter = Completer();

  WebViewAutomator._create();

  static Future<WebViewAutomator> create() async {
    debugPrint('constructing WebViewAutomator');

    var automator = WebViewAutomator._create();
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
          await webViewController.runJavaScript('''
            if (document.readyState === 'complete') {
              ___.postMessage('${WebViewEvents.pageload}');
            }
            else {
              document.onreadystatechange = () => {
                if (document.readyState === 'complete') {
                  ___.postMessage('${WebViewEvents.pageload}');
                }
              }
            }
          ''');
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
        Completer<dynamic>? completer;
        if (message.message == '${WebViewEvents.waitElement}') {
          // completer = promises[WebViewEvents.waitElement];
        }
        else if (message.message == '${WebViewEvents.pageload}') {
          // completer = promises[WebViewEvents.pageload];
        }

        // if (completer != null && !completer.isCompleted) {
        //   completer.complete(null);
        // }
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

    var swatch = Stopwatch()..start();
    while (swatch.elapsed < Duration(seconds: 10)) {
      try {
        await runJavaScriptOnElements(
          selector: targetSelector, 
          innerText: innerText,
          js: "return true;",
        );
        debugPrint('found element');
        return;
      } on NoElementFoundException {
        await Future.delayed(Duration(milliseconds: 2));
        debugPrint('not found element trying again');
      }
    }
    debugPrint('Timed out founding the element');
    throw NoElementFoundException();
  }


  Future<void> waitPageload() async {
    debugPrint('wait pageload');

    // var completer = promises[WebViewEvents.pageload];
    // if (completer != null && !completer.isCompleted) {
    //   debugPrint('webpageloadaborted');
    //   completer.completeError(WebpageLoadAbortedException());
    // }

    var completer = Completer();
    promises[WebViewEvents.pageload] = completer;
    // Future.delayed(Duration(seconds: 5), () {
    //   // completer.complete(true);
    // });
    await aaCompleter.future;
    // promises.remove(WebViewEvents.pageload);

    // var t = await webViewController.getTitle();
    // debugPrint(t);
    return;

    // completer.future.then((result) {
    //   debugPrint('wait pageload done');
    //   return;
    // }).timeout(Duration(seconds:3), onTimeout: () async {
    //   debugPrint('wait pageload timeout');
    //   var title = await webViewController.getTitle();
    //   debugPrint(title);
    // });

    // var swatch = Stopwatch()..start();
    // while (swatch.elapsed < Duration(seconds: 10)) {
      // String readyState = await webViewController.runJavaScriptReturningResult('''
      //   document.readyState;
      // ''') as String;

      // debugPrint(readyState);
      // if (readyState == 'complete') {
      //   debugPrint(swatch.toString());
      //   return;
      // }
      // Future.delayed(Duration(milliseconds: 100));
    // }
    // debugPrint('done with loop');
  }
}