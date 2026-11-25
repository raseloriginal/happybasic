import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'auth/login_page.dart';
import 'core/api.dart';
import 'core/offline.dart';
import 'core/push.dart';
import 'core/realtime.dart';
import 'core/session.dart';
import 'core/store.dart';
import 'dsr/dsr_home.dart';
import 'retailer/retailer_home.dart';
import 'sr/sr_home.dart';
import 'ui/common.dart';
import 'ui/update.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // A bug in one screen must never show a red error page to a field user.
  ErrorWidget.builder = (details) => const Material(
        child: Center(child: Padding(padding: EdgeInsets.all(24), child: Text('কিছু একটা সমস্যা হয়েছে। পেছনে গিয়ে আবার চেষ্টা করুন।', textAlign: TextAlign.center))),
      );
  await LocalStore.init();
  await ApiClient.init();
  await PushService.initLocal();
  await OfflineQueue.instance.init();
  final auth = AuthState();
  await auth.init();
  runApp(ChangeNotifierProvider.value(value: auth, child: const HappyApp()));
}

class HappyApp extends StatelessWidget {
  const HappyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'হ্যাপি বাংলাদেশ',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      // Without these delegates Flutter has no Bengali MaterialLocalizations and TextField / dialogs / date pickers crash.
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      locale: const Locale('bn', 'BD'),
      supportedLocales: const [Locale('bn', 'BD'), Locale('en')],
      home: const RoleGate(),
    );
  }
}

/// One login, three apps: the role stored on the account picks the panel.
class RoleGate extends StatefulWidget {
  const RoleGate({super.key});
  @override
  State<RoleGate> createState() => _RoleGateState();
}

class _RoleGateState extends State<RoleGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from the background: send what is waiting, reconnect the live link, refresh screens.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && context.read<AuthState>().signedIn) {
      Realtime.instance.resumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    if (!auth.ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (auth.updateMessage != null) return UpdateRequiredPage(message: auth.updateMessage!);
    if (!auth.signedIn) return const LoginPage();
    return switch (auth.role) {
      'sr' => const SrHome(),
      'dsr' => const DsrHome(),
      'retailer' => const RetailerHome(),
      _ => const LoginPage(),
    };
  }
}
