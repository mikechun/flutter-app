import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      throw new Error("NoElementFound");
    }
  """;
}

class NoElementFoundException implements Exception {}

class WebViewAutomator {
  final WebViewController controller; 

  WebViewAutomator(this.controller);

  Future<void> open({required String url}) async {
    await controller.loadRequest(Uri.parse(url));
  }

  Future<String> getLocation() async {
    return await controller.currentUrl() ?? '';
  }

  Future<String> runJavaScriptOnElements({required String selector, String innerText = '', required String js}) async {
    // Exit early on element not found errors;
    try {
      final r = await controller.runJavaScript(
        runJsAnonFunction([
          getElementsJsScript(selector, innerText),
        ])
      );
    } on PlatformException catch (e) {
      throw NoElementFoundException();
    }

    final r = await controller.runJavaScriptReturningResult(
      runJsAnonFunction([
        getElementsJsScript(selector, innerText),
        js,
        'return ""',
      ])
    );
    return r.toString();
  }

  Future<bool> type({required String selector, String innerText = '', required String value}) async {
    String result = await runJavaScriptOnElements(
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



  Future<num> find({required String selector, String innerText = ''}) async {
    String result = await runJavaScriptOnElements(
      selector: selector, 
      js: """
        return els.length;
        """
    );
    return num.parse(result);
  }

  Future<bool> click({required String selector, String innerText = ''}) async {
    String result = await runJavaScriptOnElements(
      selector: selector, 
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

  Future<bool> waitElement({required String selector, String innerText = ''}) async {
    final startTime = DateTime.now().millisecondsSinceEpoch;
    while (true) {
      try {
        String result = await runJavaScriptOnElements(
          selector: selector, 
          js: """
            return 'true';
            """,
        );
        if (result == 'true') {
          return true;
        }
      } on NoElementFoundException {
        // Fail after waiting 15 seconds
        if (DateTime.now().millisecondsSinceEpoch - startTime > 15000) {
          debugPrint('rethrowing exception');
          rethrow;
        }

        await Future.delayed(Duration(milliseconds: 25));
      }
    }
  }


  Future<bool> waitPageload() async {
    final startTime = DateTime.now().millisecondsSinceEpoch;

    while (true) {
      final result = await controller.runJavaScriptReturningResult(
        """
        document.readyState;
        """
      );
      if (result != 'complete') {
        break;
      }
      await Future.delayed(Duration(milliseconds: 25));
    }

    while (true) {
      final result = await controller.runJavaScriptReturningResult(
        """
        document.readyState;
        """
      );
      if (result == 'complete') {
        debugPrint('success');
        return true;
      }

      // Fail after waiting 10 seconds
      if (DateTime.now().millisecondsSinceEpoch - startTime > 10000) {
        debugPrint('failed');
        return false;
      }
      debugPrint(result as String);

      await Future.delayed(Duration(milliseconds: 25));
    }
  }

}