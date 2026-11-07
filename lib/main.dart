import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'screens/task_list_screen.dart';
import 'services/firebase_service.dart';
import 'services/notification_service.dart';

void main() async {
  // Ensure Flutter engine bindings are initialized before async initialization
  WidgetsFlutterBinding.ensureInitialized();

  bool isRealFirebaseConfigured = false;

  // Initialize Firebase App natively first
  try {
    await Firebase.initializeApp();
    isRealFirebaseConfigured = true;
    debugPrint('Firebase App initialized with native configuration (google-services.json).');
  } catch (e) {
    debugPrint('Native google-services.json not found: $e');
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: const FirebaseOptions(
            apiKey: 'AIzaSyDemoKeyForLab2Assignment123456',
            appId: '1:123456789012:android:demoapp12345',
            messagingSenderId: '123456789012',
            projectId: 'lab2-task-manager-demo',
          ),
        );
        debugPrint('Firebase initialized in local-only fallback mode.');
      }
    } catch (fallbackError) {
      debugPrint('Fallback Firebase initialization warning: $fallbackError');
    }
  }

  // Set cloud availability status in FirebaseService
  FirebaseService.instance.setCloudAvailable(isRealFirebaseConfigured);

  // Initialize Notification Service for local task reminder notifications
  try {
    await NotificationService.instance.initNotification();
  } catch (e) {
    debugPrint('NotificationService initialization warning: $e');
  }

  runApp(const SmartTaskApp());
}

/// Root application widget for Smart Task Manager (Lab 2)
class SmartTaskApp extends StatelessWidget {
  const SmartTaskApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Task Manager',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
      ),
      home: const TaskListScreen(),
    );
  }
}
