import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_state.dart';

class SettingsPage extends StatefulWidget {
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final settingsState = context.watch<SettingsState>();
    usernameController.text = settingsState.data.username;
    passwordController.text = settingsState.data.password;
    bool amollaMode = settingsState.data.amollaMode;

    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.displaySmall!.copyWith(
      fontWeight: FontWeight.bold,
    );
    final sectionStyle = theme.textTheme.labelLarge!.copyWith(
      fontSize: 16,
    );
    final itemStyle = theme.textTheme.displaySmall!.copyWith(
      fontSize: 16,
    );

    return SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Settings', style: headerStyle), 
            SizedBox(height: 10),
            Text('GTC Account', style: sectionStyle), 
            SizedBox(height: 10),
            Section(
              children: [
                TextField(
                  controller: usernameController,
                  obscureText: false,
                  decoration: InputDecoration(
                    border: UnderlineInputBorder(),
                    labelText: 'Username',
                  ),
                  style: itemStyle,
                ),
                SizedBox(height: 10),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    border: UnderlineInputBorder(),
                    labelText: 'Password',
                  ),
                  style: itemStyle,
                ),
                SizedBox(height: 10),
                Row(children: [
                  ElevatedButton(
                    onPressed: () async {
                      settingsState.data.username = usernameController.text;
                      settingsState.data.password = passwordController.text;
                      await settingsState.save();
                    },
                    child: Text('Save'),
                  ),
                ],)
              ],
            ),
            Section(children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Amolla Mode'),
                    Switch(
                      // This bool value toggles the switch.
                      value: amollaMode,
                      activeColor: Colors.red,
                      onChanged: (bool value) async {
                        settingsState.data.amollaMode = value;
                        await settingsState.save();
                        // This is called when the user toggles the switch.
                      },
                    ),
                ],)
              ],)
          ],
        ),
    );
  }
}

class Section extends StatelessWidget {
  const Section({
    super.key,
    required this.children,
  });

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.only(
        left: 20,
        right: 20,
        top: 10,
        bottom: 10,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: Colors.white,
      ),
      child: Column (
        children: children,
      ),
    );
  }
}

