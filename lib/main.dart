import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'controllers/auth_controller.dart';
import 'core/config/app_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'services/analytics_service.dart';
import 'services/notification_service.dart';
import 'services/revenue_cat_service.dart';
import 'services/subscription_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait — camera UX is portrait-native
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Transparent status bar so camera fills edge-to-edge
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.black,
    ),
  );

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.initialise();
  await AnalyticsService.initialise();
  await RevenueCatService.configure();

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

  runApp(
    // ProviderScope is the Riverpod root — all providers live here
    const ProviderScope(child: TaveraApp()),
  );
}

class TaveraApp extends ConsumerWidget {
  const TaveraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Mirror Supabase auth state into PostHog identity so every tracked
    // event carries the correct user ID automatically.
    ref.listen(authStateProvider, (_, authAsync) {
      final session = authAsync.valueOrNull?.session;
      if (session != null) {
        final userId = session.user.id;
        // PostHog identity
        AnalyticsService.identify(
          userId,
          properties: {
            if (session.user.email case final String email) 'email': email,
          },
        );
        // RevenueCat identity — links purchase records to this Supabase user
        RevenueCatService.identify(userId);
        // Refresh entitlement cache for the newly-signed-in user
        ref.invalidate(revenueCatPremiumProvider);
      } else {
        AnalyticsService.reset();
        RevenueCatService.reset();
        ref.invalidate(revenueCatPremiumProvider);
      }
    });

    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Tavera',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: router,
      // Prevent white flash on navigation
      builder: (context, child) => Container(
        color: Colors.black,
        child: child,
      ),
    );
  }
}
