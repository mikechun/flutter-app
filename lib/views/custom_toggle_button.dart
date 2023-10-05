import 'package:flutter/material.dart';


enum ButtonType { elevated }

class CustomToggleButton extends StatelessWidget{
  final Widget child;
  final bool pressed;
  final VoidCallback onPressed;
  late final Map<String, dynamic> style;
  late final ButtonType buttonType;

  CustomToggleButton.elevatedButton({style, required this.onPressed, required this.pressed, required this.child}) {
    buttonType = ButtonType.elevated;

    if (style != null) {
      this.style = style;
    } else {
      this.style = {};
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (buttonType == ButtonType.elevated) {
      return ElevatedButton(
        style: ElevatedButton.styleFrom(
          padding: style['padding'],
          backgroundColor: pressed ? Color.fromRGBO(211, 205, 219, 1): style['backgroundColor'],
        ),
        onPressed: onPressed,
        child: child,
      );
    } else {
      return ElevatedButton(
        style: ElevatedButton.styleFrom(
          padding: style['padding'],
          backgroundColor: pressed ? Color.fromRGBO(211, 205, 219, 1): style['backgroundColor'],
        ),
        onPressed: onPressed,
        child: child,
      );
    }
  }
}