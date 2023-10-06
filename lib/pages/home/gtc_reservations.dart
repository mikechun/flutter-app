import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tennibot/providers/settings_state.dart';
import 'package:tennibot/services/gtc_runner.dart';
import 'package:tennibot/views/court_button_selector.dart';
import 'package:tennibot/views/date_picker.dart';
import 'package:tennibot/views/duration_button_selector.dart';
import 'package:tennibot/views/custom_toggle_button.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';


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
  bool testing = false;
  GTCRunner? runner;
  bool amollaMode = false;

  Future<void> waitUntil(DateTime scheduledRun) async {
    DateTime now = DateTime.now();
    await Future.delayed(scheduledRun.difference(now));
  }

  Future<void> reserve(DateTime date, String interval, String courtNumber, DateTime? schedule, bool fast) async {
    debugPrint('reserving for $date, interval $interval, court $courtNumber, with schedule $schedule, using fast $fast');
    var now = DateTime.now();
    String snackMessage = '';

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
      snackMessage = result ? 'Reservation successful' : 'Reservation failed';
    } on RunnerCancelledException {
      snackMessage = '';
    } catch (e) {
      snackMessage = 'Reservation failed';
      debugPrint(e.toString());
    }

    if (context.mounted && snackMessage.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(snackMessage)),
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
    super.didChangeDependencies();

    var SettingsData(:username, :password, :amollaMode) = Provider.of<SettingsState>(context, listen: true).data;
    if ((runner?.username, runner?.password) != (username, password)) {
      debugPrint('username or password changed');

      if (username.isNotEmpty && password.isNotEmpty) {
        // Cancel previous runner if exists
        runner?.schedule = null;
        runner = await GTCRunner.create(username, password);
      }
    }
    amollaMode = amollaMode;
  }

  @override
  Widget build(BuildContext context) {
    WakelockPlus.enable();
    debugPrint('building');

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
          Expanded(child: runner == null ? Container() : WebViewWidget(controller: runner!.controller)),
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
                await reserve(date, duration, courtNumber, null, amollaMode);
              },
              child: const Text('Reserve'),
            ),
            SizedBox(
              width: 40,
              height: 40,
              child: CustomToggleButton.elevatedButton(
                style: {
                  'padding': EdgeInsets.zero,
                },
                pressed: runner?.schedule != null, 
                child: Icon(Icons.timer),
                onPressed: () async {
                  if (scheduleTime != null) {
                    setState(() {
                      scheduleTime = null;
                    });
                    return;
                  }

                  DateTime schedule = DateTime.now().copyWith(
                    hour: 22,
                    // hour: 12,
                    minute: 30,
                    second: 0,
                    millisecond: 0,
                    microsecond: 0,
                  );
                  setState(() {
                    scheduleTime = schedule;
                  });
                  await reserve(date, duration, courtNumber, schedule, amollaMode);
                },
              )
            ),
          ]),
        ]),
      ],
    );
  }
}
