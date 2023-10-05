import 'dart:async';

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
  bool testing = false;
  String username;
  String password;
  DateTime? sessionExpiration;
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

  Future<void> login() async {
    if (username.isEmpty || password.isEmpty) {
      return;
    }

    DateTime now = DateTime.now();
    if (sessionExpiration != null) {
      if (sessionExpiration!.subtract(Duration(hours: 1)).isAfter(now)) {
        // Skip if there more than 1 hour left on expiry
        return;
      }
      // Logout and login again
      await _automator.open(url: 'https://gtc.clubautomation.com/logout');
      await _automator.waitPageLoad();
    }

    debugPrint('logging in');
    await _automator.open(url: 'https://gtc.clubautomation.com');
    await _automator.waitPageLoad();

    String url = await _automator.getLocation();
    if (url == 'https://gtc.clubautomation.com/member') {
      debugPrint('already logged in');
      return;
    }

    // Enter credentials
    await _automator.type(selector: '#login', value: username);
    await _automator.type(selector: '#password', value: password);
    await _automator.click(selector: '#loginButton');
    await _automator.waitPageLoad();

    url = await _automator.getLocation();
    if (url != 'https://gtc.clubautomation.com/member') {
      throw AuthenticationException();
    }

    sessionExpiration = now.add(Duration(hours: 8));
    debugPrint('logging in success');
  }

  Future<void> navigateBookingPage() async {
    await _automator.open(url: 'https://gtc.clubautomation.com/event/reserve-court-new');
    await _automator.waitPageLoad();
  }

  Future<List<String>> findCourt({required DateTime date, required int duration, int courtNum = -1, int timeoutSec = 5}) async {
    await configureSearchForm(date, duration, courtNum);

    await _automator.click(selector: '#reserve-court-search');
    debugPrint('clicked courts search');

    await _automator.waitElement(
      listenerSelector: '#reserve-court-new',
      targetSelector: '#times-to-reserve > tbody > tr > td > a, .court-not-available-text'
    );
    debugPrint('courts results received');

    String? availabilityHTML = await _automator.getHTMLorNULL(selector: '#times-to-reserve > tbody > tr');
    if (availabilityHTML == null) {
      HighlightIO.sendLog(
        '',
        { 
          'ballmachine': 'false',
          'reservedate': date.toIso8601String(),
          'court': courtNum.toString(),
          'username': username,
        },
      );
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
        'reservedate': date.toIso8601String(),
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
      throw TimeoutException('reservation diabled in test mode');
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

  Future<bool> fastReserve(DateTime date, int duration, int courtNum) async {
    configureSearchForm(date, duration, courtNum);

    await _automator.webViewController.runJavaScript('newMemberReg.reserveCourtConfirm()');

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

  Future<bool> run(DateTime date, int duration, int courtNumber, DateTime scheduledRun, bool fast) async {
      DateTime now = DateTime.now();

      // Prevent session expiration by delaying login until 1 hour before the scheduled run. 
      await Future.delayed(scheduledRun!.subtract(const Duration(hours: 1)).difference(now));

      await login();
      await navigateBookingPage();

      // final targetTime = formatCourtTime(date);
      if (scheduledRun.isAfter(DateTime.now())) {
        debugPrint('waiting for the run $scheduledRun');
        await waitUntil(scheduledRun);
      }

      int nextCourt = courtNumber;
      // Run find court and send logs;
      List<String> courts = [];

      // Wait up to 1 seconds for the page to update with new court times
      bool timedOut = false;
      await Future.doWhile(() async {
        if (timedOut) { return false; }

        debugPrint('finding courts');
        try {
          courts = await findCourt(date: date, duration: duration, courtNum: -1);
        } on CourtNotAvailableException {
          debugPrint('court not found.. trying again');
          await Future.delayed(Duration(milliseconds: 0));
          return true;
        }
        return false;
      }).timeout(Duration(seconds: 1), onTimeout: () async {
        timedOut = true;
        debugPrint('stopping');
        throw TimeoutException('Could not find an available court');
      });
        
      //Reserve the timeslot try up to 5 times 
      for (int i = 0; i < 5; i++) {
        if (!courts.contains(formatCourtTime(date))) {
          debugPrint('failed to find time slot');
          // Given time is not available.  Pick a different time and try again
          return false;
        }

        try {
          bool status = false;
          if (fast) {
            status = await fastReserve(date, duration, nextCourt);
          } else {
            courts = await findCourt(date: date, duration: duration, courtNum: nextCourt);
            status = await reserve(date);
          }
          debugPrint('reserve successful');
          return true;
        } on TimeslotUnavailableException {
          debugPrint('Failed to grab the timeslot.');
          if (nextCourt != -1) {
            nextCourt = -1;
          }
        }
      }

      return false;
  }

  Future<String> test () async {
    var js = await _automator.webViewController.runJavaScriptReturningResult("""
      (() => {
        return document.getElementById('reserve-court-filter');
      })();
    """);
    debugPrint(js.toString());
    return js.toString();
  }
  
  Future<void> configureSearchForm (DateTime date, int duration, int courtNum) async {
    var formattedDate = '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/${date.year}';
    final selectHTML = await _automator.getHTML(selector: '#court');
    final courtValues = parseCourtValues(selectHTML);
    // -1 is for all courts
    String courtId = '-1';
    if (courtValues.containsKey(courtNum.toString())) {
      courtId = courtValues[courtNum.toString()] as String;
    } 

    // // tennis location is '1'
    await _automator.set(selector: '#location', value: '1');
    await _automator.set(selector: '#court', value: courtId);
    await _automator.check(selector: '#ball_machine-0');
    await _automator.set(selector: '#date', value: formattedDate);
    await _automator.check(selector: '#interval-$duration');
    await _automator.set(selector: '#timeFrom', value: '0');
    await _automator.set(selector: '#timeTo', value: '24');
    await _automator.set(selector: '#time-reserve', value: (date.millisecondsSinceEpoch / 1000).floor().toString());
    await _automator.set(selector: '#location-reserve', value: '1');
    await _automator.set(selector: '#surface-reserve', value: '2');
    await _automator.set(selector: '#join-waitlist-case', value: '1');

    debugPrint('configured courts search');
  }
}