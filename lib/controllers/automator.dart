import 'dart:html';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

String runJsAnonFunction(List<String> scripts) {
  return [
    "(() => {",
    ...scripts,
    "})();"
  ].join('\n');
}

String getElementsJsScript(selector, innerText) {
  return """
    var els = Array.from(document.querySelectorAll("$selector"));
    if ("$innerText" && els) {
      els = els.filter(el => el.innerText == "$innerText");
    }

    if (!els || !els.length) {
      return '_NoElementFoundException()';
    }
  """;
}


class WebViewAutomator {
  final WebViewController controller; 

  WebViewAutomator(this.controller);

  Future<void> open({required String url}) async {
    await controller.loadRequest(Uri.parse(url));
  }

  Future<String> getLocation() async {
    return await controller.currentUrl() ?? '';
  }

  Future<bool> type({required String selector, String innerText = '', required String value}) async {
    final r = await controller.runJavaScriptReturningResult(
      runJsAnonFunction([
        getElementsJsScript(selector, innerText),
        """
        for (var c of "$value") {
          var key = {"key": c};
          for (el of els) {
            el.dispatchEvent(new KeyboardEvent('keydown', key));
            el.dispatchEvent(new KeyboardEvent('input', key));
            el.dispatchEvent(new KeyboardEvent('keyup', key));
            el.value += c;
          }
        }
        return 'true';
        """
      ])
    );
    return r == 'true';
  }
  
  Future<bool> set({required String selector, String innerText = '', required String value}) async {
    final r = await controller.runJavaScriptReturningResult(
      runJsAnonFunction([
        getElementsJsScript(selector, innerText),
        // JS Script to set value of items
        """
        for (el of els) {
          el.value = "$value";
        }
        return 'true';
        """
      ])
    );
    return r == 'true';
  }

  Future<String> getHTML({required String selector}) async {
    debugPrint('gettingHTML: $selector');
    final r = await controller.runJavaScriptReturningResult(
      runJsAnonFunction([
        getElementsJsScript(selector, ''),
        // JS Script to get HTML. Returns first item only
        """
        return els[0].outerHTML;
        """
      ])
    );
    return r.toString();
  }



  Future<num> find({required String selector, String innerText = ''}) async {
    final r = await controller.runJavaScriptReturningResult(
      runJsAnonFunction([
        getElementsJsScript(selector, innerText),
        """
        return els.length;
        """
      ])
    );
    if (r == 'false') {
      return 0;
    }
    return r as num;
  }

  Future<bool> click({required String selector, String innerText = ''}) async {
    final r = await controller.runJavaScriptReturningResult(
      runJsAnonFunction([
        getElementsJsScript(selector, innerText),
        """
        els.forEach(el => el.click());
        return true;
        """
      ])
    );
    return r == 'true';
  }

  Future<bool> check({required String selector, String innerText = ''}) async {
    final r = await controller.runJavaScriptReturningResult(
      runJsAnonFunction([
        getElementsJsScript(selector, innerText),
        """
        els.forEach(el => el.checked = true);
        return true;
        """
      ])
    );
    return r == 'true';
  }

  Future<bool> waitElement({required String selector, String innerText = ''}) async {
    final startTime = DateTime.now().millisecondsSinceEpoch;
    while (true) {
      final r = await controller.runJavaScriptReturningResult(
        runJsAnonFunction([
          getElementsJsScript(selector, innerText),
          """
          return 'true';
          """,
        ])
      );
      if (r == 'true') {
        return true;
      }
      // Fail after waiting 15 seconds
      if (DateTime.now().millisecondsSinceEpoch - startTime > 15000) {
        return false;
      }

      await Future.delayed(Duration(milliseconds: 25));
    }
  }


  Future<bool> waitPageload() async {
    final startTime = DateTime.now().millisecondsSinceEpoch;

    while (true) {
      final r = await controller.runJavaScriptReturningResult(
        """
        document.readyState;
        """
      );
      if (r != 'complete') {
        break;
      }
      await Future.delayed(Duration(milliseconds: 25));
    }

    while (true) {
      final r = await controller.runJavaScriptReturningResult(
        """
        document.readyState;
        """
      );
      if (r == 'complete') {
        debugPrint('success');
        return true;
      }

      // Fail after waiting 10 seconds
      if (DateTime.now().millisecondsSinceEpoch - startTime > 10000) {
        debugPrint('failed');
        return false;
      }
      debugPrint(r as String);

      await Future.delayed(Duration(milliseconds: 25));
    }
  }

}