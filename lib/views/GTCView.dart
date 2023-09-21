import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tennibot/controllers/automator.dart';
import 'package:tennibot/providers/settings_state.dart';
import 'package:tennibot/views/CourtButtonSelector.dart';
import 'package:tennibot/views/DatePicker.dart';
import 'package:tennibot/views/DurationButtonSelector.dart';
import 'package:webview_flutter/webview_flutter.dart';

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


class TimeslotUnavailableException implements Exception {}
class CourtNotAvailableException implements Exception {}
class AuthenticationException implements Exception {}

class GTCViewComponent extends StatefulWidget {
  final String initialUrl = 'https://gtc.clubautomation.com/';

  GTCViewComponent();

  @override
  State<GTCViewComponent> createState() => _GTCViewComponentState();
}

class _GTCViewComponentState extends State<GTCViewComponent> {
  late final WebViewAutomator _automator;
  DateTime date = DateTime.now().copyWith(hour: 19, minute: 30, second: 0).add(const Duration(days: 8));
  String courtNumber = '1';
  String duration = '90';
  bool running = false;
  late String username;
  late String password;

  @override
  void initState() {
    debugPrint('initializing GTCView state');
    super.initState();

    _automator = WebViewAutomator();
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

    await _automator.click(selector: '#loginButton');
    await _automator.waitPageload();

    url = await _automator.getLocation();
    if (url != 'https://gtc.clubautomation.com/member') {
      throw AuthenticationException();
    }

    debugPrint('logging in success');
  }

  navigateBookingPage() async {
    await _automator.click(selector: '#menu_reserve_a_court');
    await _automator.waitPageload();
  }

  Future<List<String>> findCourt({required DateTime date, required int duration, int courtNum = -1, int timeoutSec = 5, int refreshDelayMSec = 100}) async {
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
    return courtTimes;
  }

  Future<bool> reserve(DateTime date) async {
    String time = formatCourtTime(date);

    await _automator.click(selector: '#times-to-reserve > tbody > tr > td > a', innerText: time);
    await _automator.waitElement(
      listenerSelector: '#reserve-court-new',
      targetSelector: '.confirm-reservation-dialog',
    );

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
      await navigateBookingPage();

      if (scheduledRun != null) {
        await waitUntil(scheduledRun);
      }

      try {
        var swatch = Stopwatch()..start();
        while (swatch.elapsed < Duration(seconds: 1)) {
          try {
            List<String> courts = await findCourt(date: date, duration: duration, courtNum: courtNumber, refreshDelayMSec: 10);
            final targetTime = formatCourtTime(date);

            if (!courts.contains(targetTime)) {
              // Given time is not available.  Pick a different time and try again
              return false;
            }
            await reserve(date);
            return true;
          } on CourtNotAvailableException {
            // try again. this is likely because the website has not refreshed yet.
            await Future.delayed(Duration(milliseconds: 1000));
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
      return true;
  }

  @override
  Widget build(BuildContext context) {
    final settingsState = context.watch<SettingsState>();
    username = settingsState.data.username;
    password = settingsState.data.password;

    const double buttonWidth = 150;
    const double menuHeight = 615;
    final ButtonStyle secondaryButtonStyle = TextButton.styleFrom(
      fixedSize: Size.fromWidth(buttonWidth),
      alignment: Alignment.centerLeft,
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Goldman Tennis Bot'),
        // This drop down menu demonstrates that Flutter widgets can be shown over the web view.
      ),
      // body: Container(),
      body: Column(
        children: [
          Expanded(child: WebViewWidget(controller: _automator.webViewController)),
          DatePicker(
            date: date, 
            buttonStyle: secondaryButtonStyle,
            onChange: (newDate) {
              setState(() {
                date = newDate;
              });
            }
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              DurationButtonSelector(
                text: '$duration Min',
                buttonStyle: secondaryButtonStyle, 
                menuWidth: buttonWidth,
                menuHeight: menuHeight,
                onSelect: (newDuration) {
                  setState(() {
                    duration = newDuration;
                  });
                },
              ),
              CourtButtonSelector(
                text: courtNumber == '-1' ? 'Any Courts' : 'Court $courtNumber',
                buttonStyle: secondaryButtonStyle, 
                menuWidth: buttonWidth,
                menuHeight: menuHeight,
                onSelect: (newCourtNumber) {
                  setState(() {
                    courtNumber = newCourtNumber;
                  });
                },
              ),
            ],
          ),
             Stack(
              children: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              fixedSize: Size.fromWidth(150),
            ),
            onPressed: 
              running ? null : 
            () async {
              setState(() {
                running = true;
              });
              await run(date, int.parse(duration), int.parse(courtNumber), null);
              setState(() {
                running = false;
              });
            },
            child: const Text('Reserve'),
          ),
                Positioned(
                  right: 12,
                  top: 14,
                  child: 
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: 
                        running ? CircularProgressIndicator(
                          strokeWidth: 3,
                        ) : null,
                  ),
            ),
          ]),
        ],
      )
    );
  }
}

  Future<void> waitUntil(DateTime scheduledRun) async {
    DateTime now = DateTime.now();
    await Future.delayed(scheduledRun.difference(now));
  }