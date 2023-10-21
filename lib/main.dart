import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tennibot/services/highlight_io.dart';
import 'package:workmanager/workmanager.dart';
import 'providers/settings_state.dart';
import 'pages/settings/settings.dart';
import 'pages/home/home.dart';

void main() async {
  // Make flutter_inappwebview available during plugin initialization
  WidgetsFlutterBinding.ensureInitialized();

  Workmanager().initialize(
    callbackDispatcher, // The top level function, aka callbackDispatcher
    isInDebugMode: true // If enabled it will post a notification whenever the task is running. Handy for debugging tasks
  );
  Workmanager().registerOneOffTask("task-identifier", "simpleTask");


  runApp(const App());
}

@pragma('vm:entry-point') // Mandatory if the App is obfuscated or using Flutter 3.1+
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) {
    print("Native called background task: $task"); //simpleTask will be emitted here.
    HighlightIO.sendLog(
      'Native called background task',
      {},
    );
    return Future.value(true);
  });
}


class App extends StatelessWidget {
  const App({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      // Load settings data as soon as possible https://lakshydeep-14.medium.com/double-d-triple-dots-in-flutter-dbe2a42dd464
      create: (context) => SettingsState()..load(),
      lazy: false,
      child: MaterialApp(
        title: 'Tennis Reservation App',
        theme: ThemeData(
          useMaterial3: true,
        ),
        home: HomePage(),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  var selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Scaffold(
          body: Row(
            children: [
              SafeArea(
                child: NavigationRail(
                  extended: false,
                  destinations: [
                    NavigationRailDestination(
                      icon: Icon(Icons.home),
                      label: Text('Home'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings),
                      label: Text('Settings'),
                    ),
                  ],
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (value) {
                    setState(() {
                      selectedIndex = value;
                    });
                  },
                ),
              ),
              Expanded(
                child: SafeArea(
                child: Container(
                  child: IndexedStack(
                    index: selectedIndex,
                    children: [
                      BrowserPage(),
                      SettingsPage(),
                    ],
                  ),
                ),
                )
              ),
            ],
          ),
        );
      }
    );
  }
}
