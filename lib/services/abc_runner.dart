import 'package:flutter/material.dart';

class ABCRunner {
  String name;

  ABCRunner(this.name);

  Future<void> run() async {
    for (int i = 0; i < 100 ; i++) {
      await Future.delayed(Duration(seconds: 1));
      debugPrint('running $i');
    }

    return;
  }
}