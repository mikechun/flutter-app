import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:tennibot/services/highlight_io.dart';
import 'package:tennibot/services/webview_automator.dart';
import 'package:webview_flutter/webview_flutter.dart';

class TimeslotUnavailableException implements Exception {}
class CourtNotAvailableException implements Exception {}
class AuthenticationException implements Exception {}

Map<String, String> parseCourtValues(String html) {
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

Future<void> waitUntil(DateTime scheduledRun) async {
  DateTime now = DateTime.now();
  await Future.delayed(scheduledRun.difference(now));
}

class GTCRunner {
  bool testing = true;
  String username;
  String password;
  late WebViewAutomator _automator;

  GTCRunner._create(this.username, this.password);

  Future<void> init() async {
    _automator = await WebViewAutomator.create();
  }

  static Future<GTCRunner> create(username, password) async {
    GTCRunner runner = GTCRunner._create(username, password);
    await runner.init();
    return runner;
  }

  WebViewController get controller {
    return _automator.webViewController;
  }

  login() async {
    if (username.isEmpty || password.isEmpty) {
      return;
    }

    debugPrint('logging in');
    await _automator.open(url: 'https://gtc.clubautomation.com');
    await _automator.waitPageload();

    String url = await _automator.getLocation();
    if (url == 'https://gtc.clubautomation.com/member') {
      debugPrint('already logged in');
      return;
    }

    debugPrint('typing');
    await _automator.type(selector: '#login', value: username);
    await _automator.type(selector: '#password', value: password);
    debugPrint('clicking');

    // await _automator.click(selector: '#loginButton');
    // await _automator.waitPageload();

    // url = await _automator.getLocation();
    // if (url != 'https://gtc.clubautomation.com/member') {
    //   throw AuthenticationException();
    // }

    debugPrint('logging in success');
  }

  navigateBookingPage() async {
    await _automator.click(selector: '#menu_reserve_a_court');
    await _automator.waitPageload();
  }

  Future<List<String>> findCourt({required DateTime date, required int duration, int courtNum = -1, int timeoutSec = 5}) async {
    String courtId = '-1';
    var formattedDate = '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/${date.year}';

    // tennis location is '1'
    await _automator.set(selector: '#location', value: '1');
    // set date
    await _automator.set(selector: '#date', value: formattedDate);
    // set duration
    await _automator.check(selector: '#interval-$duration');
    //
    await _automator.set(selector: '#timeFrom', value: '0');
    await _automator.set(selector: '#timeTo', value: '24');

    final selectHTML = await _automator.getHTML(selector: '#court');
    final courtValues = parseCourtValues(selectHTML);

    if (courtValues.containsKey(courtNum.toString())) {
      courtId = courtValues[courtNum.toString()] as String;
    } 

    await _automator.set(selector: '#court', value: courtId);
    debugPrint('configured courts search');

    await _automator.click(selector: '#reserve-court-search');
    debugPrint('clicked courts search');
    await _automator.waitElement(
      listenerSelector: '#reserve-court-new',
      targetSelector: '#times-to-reserve > tbody > tr > td > a, .court-not-available-text'
    );
    debugPrint('courts results received');

    String? availabilityHTML = await _automator.getHTMLorNULL(selector: '#times-to-reserve > tbody > tr');
    if (availabilityHTML == null) {
      throw CourtNotAvailableException();
    }

    debugPrint('parsing court times');
    List<String> courtTimes = [];

    var matches = RegExp(r'\d?\d:\d\d ?(am|pm)').allMatches(availabilityHTML);
    for (final m in matches) {
      courtTimes.add(m[0] as String);
    }

    HighlightIO.sendLog(
      courtTimes.toString(),
      { 
        'ballmachine': 'false',
        'reservedate': formattedDate,
        'court': courtNum.toString(),
        'username': username,
      },
    );
    return courtTimes;
  }

  Future<bool> reserve(DateTime date) async {
    String time = formatCourtTime(date);

    await _automator.click(selector: '#times-to-reserve > tbody > tr > td > a', innerText: time);
    await _automator.waitElement(
      listenerSelector: '#reserve-court-new',
      targetSelector: '.confirm-reservation-dialog',
    );

    if (testing) {
      return false;
    }

    try {
      await _automator.click(selector: '#confirm');
    } on NoElementFoundException {
      // If confirm button cannot be found, close button should be present
      String buttonHTML = await _automator.getHTML(selector: '#button-ok');
      if (buttonHTML.contains('Close</button>')) {
        debugPrint('Failed to book');
        await _automator.click(selector: '#button-ok');
        throw TimeslotUnavailableException();
      }
      // If close button is not found, then document structure must have changed
      rethrow;
    }

    await _automator.waitElement(
      listenerSelector: '#reserve-court-popup-new',
      targetSelector: '#button-ok',
    );
    String buttonHTML = await _automator.getHTML(selector: '#button-ok');
    if (buttonHTML.contains('Close</button>')) {
      debugPrint('Failed to book');
      await _automator.click(selector: '#button-ok');
      throw TimeslotUnavailableException();
    } else {
      debugPrint('Success in booking');
      await _automator.click(selector: '#button-ok');
      return true;
    }
  }

  String formatCourtTime(DateTime date) {
    final String ampm = date.hour < 12 ? 'am' : 'pm';
    final String hour = date.hour < 13 ? '${date.hour}' : '${date.hour % 12}';
    final String minute = date.minute.toString().padLeft(2, '0');
    final String time = '$hour:$minute$ampm';
    return time;
  }

  Future<void> ajaxReserve() async {
    // String tokenHTML = await _automator.getHTML(selector: '#event_member_token_reserve_court');
    // String eventMemberToken = RegExp(r'.*value="(\S+)".+').firstMatch(tokenHTML)?.group(1) ?? '';
    await login();
    await navigateBookingPage();
  }

  Future<bool> run(DateTime date, int duration, int courtNumber, DateTime? scheduledRun) async {
      await login();
      if (duration != 100) return false;

      await navigateBookingPage();

      if (scheduledRun != null) {
        debugPrint('waiting for the run $scheduledRun');
        await waitUntil(scheduledRun);
      }

      try {
        var swatch = Stopwatch()..start();
        // Try to find a court in 2 seconds.  At most 40 requests.
        // Assuming that this EPOCH time does not driff more than 1 seconds.
        int sleepDelayMs = 10;
        while (swatch.elapsed < Duration(seconds: 1)) {
          try {
            debugPrint('Finding court. ${DateTime.now()}');
            List<String> courts = await findCourt(date: date, duration: duration, courtNum: courtNumber);
            final targetTime = formatCourtTime(date);

            if (!courts.contains(targetTime)) {
              // Given time is not available.  Pick a different time and try again
              return false;
            }
            await reserve(date);
            return true;
          } on CourtNotAvailableException {
            // try again. this is likely because the website has not refreshed yet.
            debugPrint('Court Not available: trying again');

            // Exponential delay up to 200ms;
            await Future.delayed(Duration(milliseconds: sleepDelayMs));
            sleepDelayMs = min(sleepDelayMs * 2, 200);
            continue;
          } on TimeslotUnavailableException {
            // If failed to get the court that we wanted, try to get any court
            if (courtNumber > 0) {
              courtNumber = -1;
            }
            continue;
          } 
        }
      } on NoElementFoundException catch (e, s) {
        debugPrint('Failed. Element not found during the run. Website may have changed');
        debugPrintStack(stackTrace: s);
        return false;
      } on TimeoutException catch (e, s) {
        // Failed to find elements in time. Likely due to server not updating UI as expected
        debugPrint('Failed. Website failed to update during the run. Website may have changed');
        debugPrintStack(stackTrace: s);
        return false;
      }
      return false;
  }
}