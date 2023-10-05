import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tennibot/providers/settings_state.dart';
import 'package:tennibot/services/gtc_runner.dart';
import 'package:tennibot/views/court_button_selector.dart';
import 'package:tennibot/views/date_picker.dart';
import 'package:tennibot/views/duration_button_selector.dart';
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
  // late final WebViewAutomator _automator;
  DateTime date = DateTime.now().copyWith(hour: 19, minute: 30, second: 0).add(const Duration(days: 8));
  String courtNumber = '-1';
  String duration = '90';
  bool running = false;
  DateTime? scheduleTime;
  bool testing = true;
  GTCRunner? runner;
  bool amolla = false;

  Finalizer finalizer = Finalizer((p0) {
    debugPrint('ABC Finalizer');
  });

  Future<void> waitUntil(DateTime scheduledRun) async {
    DateTime now = DateTime.now();
    await Future.delayed(scheduledRun.difference(now));
  }

  Future<void> reserve(DateTime date, String interval, String courtNumber, DateTime? schedule, bool fast) async {
    debugPrint('reserving for $date, interval $interval, court $courtNumber, with schedule $schedule, using fast $fast');
    var now = DateTime.now();

    if (schedule != null && schedule.isAfter(now)) {
      var durationUntilSchedule = schedule.difference(now);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
              'Scheduled to run in ${durationUntilSchedule.toString()}'),
        ),
      );
    } else {
      schedule = now;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
              'Reserving tennis court'),
        ),
      );
    }

    bool result = false;
    try{
      result = await runner!.run(date, int.parse(duration), int.parse(courtNumber), schedule, fast);
    } catch (e) {
      debugPrint(e.toString());
    }

    if (context.mounted) {
      String message =
          result ? 'Reservation successful' : 'Reservation failed';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(message)),
      );
    }
  }

  @override
  void initState() {
    debugPrint('initializing GTCView state');
    super.initState();
  }

  @override
  void didChangeDependencies() async {
    // TODO: implement didChangeDependencies
    super.didChangeDependencies();
    var data = Provider.of<SettingsState>(context, listen: false).data;

    var SettingsData(:username, :password, :amollaMode) = Provider.of<SettingsState>(context, listen: true).data;
    if ((runner?.username, runner?.password) != (username, password)) {
      debugPrint('username or password changed');
      runner = await GTCRunner.create(username, password);
    }
    print('dep change');
    print(data.toJSON());
    print('$username, $password, $amollaMode');

    amolla = amollaMode;
  }

  @override
  Widget build(BuildContext context) {
    // final settingsState = context.watch<SettingsState>();
    debugPrint('building');
    print(amolla);

    const double buttonWidth = 150;
    const double menuHeight = 615;
    final ButtonStyle secondaryButtonStyle = TextButton.styleFrom(
      fixedSize: Size.fromWidth(buttonWidth),
      alignment: Alignment.centerLeft,
    );

    return 
      Column(
        children: [
          AppBar(
            title: const Text('Goldman Tennis Bot'),
            // This drop down menu demonstrates that Flutter widgets can be shown over the web view.
          ),
          runner != null ? Expanded(child: WebViewWidget(controller: runner!.controller)) : Container(),
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
        Stack(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            ElevatedButton(
              onPressed: () async {
                await reserve(date, duration, courtNumber, null, amolla);
              },
              child: const Text('Reserve'),
            ),
            SizedBox(
              width: 40,
              height: 40,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.all(0),
                ),
                child: Icon(Icons.timer),
                onPressed: () async {
                  DateTime schedule = DateTime.now().copyWith(
                    hour: 12,
                    minute: 30,
                    second: 0,
                    millisecond: 0,
                    microsecond: 0,
                  );
                  scheduleTime = schedule;
                  await reserve(date, duration, courtNumber, schedule, amolla);
                },
              ),
            ),
          ]),
        ]),
      ],
    );
  }
}
