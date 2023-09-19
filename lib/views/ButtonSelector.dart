import 'package:flutter/material.dart';

class ButtonSelector extends StatelessWidget {
  const ButtonSelector({
    super.key,
    required this.buttonStyle,
    required this.menuWidth,
    required this.menuHeight,
    required this.text,
    required this.menuItems,
    required this.onSelect,
    required this.icon,
    required this.menuItemTextRender,
  });

  final ButtonStyle buttonStyle;
  final String text;
  final List<String> menuItems;
  final ValueChanged<String> onSelect;
  final Icon icon;
  final double menuWidth;
  final double menuHeight;
  final String Function(String value) menuItemTextRender;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      style: MenuStyle(
        maximumSize: MaterialStatePropertyAll(Size(menuWidth, menuHeight))),
      builder:
        (BuildContext context, MenuController controller, Widget? child) {
        return TextButton.icon(
          style: buttonStyle,
          label: Text(text),
          icon: icon,
          onPressed: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
        );
      },
      menuChildren: List<MenuItemButton>.generate(
        menuItems.length,
        (int index) => MenuItemButton(
          style: MenuItemButton.styleFrom(fixedSize: Size.fromWidth(menuWidth)),
          onPressed: () => onSelect(menuItems[index]),
          child: Text(menuItemTextRender(menuItems[index])),
        ),
      ),
    );
  }
}