import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final Map<WebViewEvents, Completer> promises = {};

  WebViewAutomator() {
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
    webViewController..setNavigationDelegate(
      NavigationDelegate(
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
      ),
    )
    ..addJavaScriptChannel(
      '___',
      onMessageReceived: (JavaScriptMessage message) {
        Completer<dynamic>? completer;
        if (message.message == '${WebViewEvents.waitElement}') {
          completer = promises[WebViewEvents.waitElement];
        }
        else if (message.message == '${WebViewEvents.pageload}') {
          completer = promises[WebViewEvents.pageload];
        }

        if (completer != null && !completer.isCompleted) {
          completer.complete(null);
        }
        debugPrint(message.message);
      },
    );

    // #docregion platform_features
    if (webViewController.platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(true);
      (webViewController.platform as AndroidWebViewController)
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
    /*
    var completer = promises[WebViewEvents.waitElement];
    if (completer != null && !completer.isCompleted) {
      completer.completeError(WaitElementAbortedException());
    }

    var newCompleter = Completer();
    promises[WebViewEvents.waitElement] = newCompleter;
    Future.delayed(Duration(milliseconds: 10000), () {
      if (!newCompleter.isCompleted) {
        newCompleter.completeError(TimeoutException('Mutation not detected on element $listenerSelector'));
      }
    });

    // Register element observer
    await runJavaScriptOnElements(
      selector: listenerSelector, 
      js: """
        var observer = new MutationObserver(() => {
          ___.postMessage('${WebViewEvents.waitElement}');
          observer.disconnect();
        });

        observer.observe(els[0], { attributes: true, childList: true, subtree: true });
        return true;
        """
    );
    await newCompleter.future;
    await runJavaScriptOnElements(
      selector: targetSelector, 
      innerText: innerText,
      js: "return true;",
    );
    */

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
    debugPrint('not found element failing');
    throw TimeoutException('Element $targetSelector could not be found');
  }


  Future<void> waitPageload() async {
    debugPrint('wait pageload');

    var completer = promises[WebViewEvents.pageload];
    if (completer != null && !completer.isCompleted) {
      completer.completeError(WebpageLoadAbortedException());
    }

    promises[WebViewEvents.pageload] = Completer();
    await promises[WebViewEvents.pageload]!.future;
    promises.remove(WebViewEvents.pageload);
    debugPrint('wait pageload done');
  }
}