import 'package:flutter/material.dart';
import 'package:tennibot/views/button_selector.dart';

class DurationButtonSelector extends StatelessWidget{
  final ButtonStyle buttonStyle;
  final double menuWidth;
  final double menuHeight;
  final List<String> menuItems = ['30', '60', '90'];
  final ValueChanged<String> onSelect;
  final String text;

  DurationButtonSelector({
    required this.buttonStyle,
    required this.onSelect,
    required this.text,
    required this.menuWidth,
    required this.menuHeight,
  });

  @override
  Widget build(BuildContext context) {
    return ButtonSelector(
      buttonStyle: buttonStyle,
      menuWidth: menuWidth,
      menuHeight: menuHeight,
      text: text,
      icon: const Icon(Icons.link),
      menuItems: menuItems,
      menuItemTextRender: (value) => '$value Min',
      onSelect: onSelect);
  }
}
