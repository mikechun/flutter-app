import 'dart:async';

import 'package:flutter/material.dart';

// import 'package:flutter/material.dart';

class ABCRunner {
  final Map<String, Completer> comps = {};
  Completer comp = Completer();

  Future<void> wait() async {
    debugPrint('hi');
    // var completer = Completer();
    // comps['h1'] = completer;

    // Future.delayed(Duration(seconds: 5), (){ completer.complete(true);});

    return comp.future;
  }

  Future<void> wait2() async {
    Completer com = Completer();
    return runZoned(() {
      return com.future;
    }, zoneValues: { #comp: com});
  }

  Future<void> wait3() async {
    debugPrint('hi3');
    return;
  }
}