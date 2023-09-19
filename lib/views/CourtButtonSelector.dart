import 'package:flutter/material.dart';
import 'package:tennibot/views/ButtonSelector.dart';

class CourtButtonSelector extends StatelessWidget{
  final ButtonStyle buttonStyle;
  final double menuWidth;
  final double menuHeight;
  final List<String> menuItems = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '13', '16', '17', '18'];
  final ValueChanged<String> onSelect;
  final String text;

  CourtButtonSelector({
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
      icon: const Icon(Icons.format_list_numbered),
      menuItems: menuItems,
      menuItemTextRender: (value) => 'Court $value',
      onSelect: onSelect);
  }
}
