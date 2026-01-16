import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:webview_flutter/webview_flutter.dart';

const String kBaseUrl = 'https://carby.najd-almotatorh.com/';
const String kDefaultTitle = 'Carby';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await NotificationService.instance.init();
  runApp(const CarbyApp());
}

class CarbyApp extends StatelessWidget {
  const CarbyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kDefaultTitle,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      home: const CarbyWebViewScreen(),
    );
  }
}

class CarbyWebViewScreen extends StatefulWidget {
  const CarbyWebViewScreen({super.key});

  @override
  State<CarbyWebViewScreen> createState() => _CarbyWebViewScreenState();
}

class _CarbyWebViewScreenState extends State<CarbyWebViewScreen> {
  late final WebViewController _controller;
  String? _fcmToken;
  String _currentUrl = kBaseUrl;

  @override
  void initState() {
    super.initState();
    NotificationService.instance.setOpenUrlHandler(_openUrl);

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            _currentUrl = url;
            _sendTokenToPage();
          },
          onNavigationRequest: (request) {
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(kBaseUrl));

    _initFcmToken();
  }

  void _initFcmToken() {
    final messaging = FirebaseMessaging.instance;
    messaging.getToken().then((token) {
      if (token == null) return;
      _fcmToken = token;
      _sendTokenToPage();
    });
    messaging.onTokenRefresh.listen((token) {
      _fcmToken = token;
      _sendTokenToPage();
    });
  }

  bool _isBaseHost(String url) {
    final baseHost = Uri.parse(kBaseUrl).host;
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return uri.host == baseHost;
  }

  void _sendTokenToPage() {
    final token = _fcmToken;
    if (token == null) return;
    if (!_isBaseHost(_currentUrl)) return;

    final encoded = Uri.encodeComponent(token);
    final platform = Platform.isIOS ? 'ios' : 'android';
    final js = """
(function() {
  try {
    fetch('/app_register_token.php', {
      method: 'POST',
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: 'token=$encoded&platform=$platform'
    });
  } catch (e) {}
})();
""";
    _controller.runJavaScript(js);
  }

  void _openUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (uri.scheme.isEmpty) {
      final resolved = Uri.parse(kBaseUrl).resolveUri(uri);
      _controller.loadRequest(resolved);
      return;
    }
    _controller.loadRequest(uri);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: WebViewWidget(controller: _controller),
      ),
    );
  }
}

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  AndroidNotificationChannel? _channel;
  void Function(String url)? _openUrl;
  String? _pendingUrl;

  void setOpenUrlHandler(void Function(String url) handler) {
    _openUrl = handler;
    if (_pendingUrl != null) {
      handler(_pendingUrl!);
      _pendingUrl = null;
    }
  }

  Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();

    await _localNotifications.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          _handleOpen(payload);
        }
      },
    );

    _channel = const AndroidNotificationChannel(
      'carby_default',
      'Carby Notifications',
      description: 'Notifications from Carby',
      importance: Importance.high,
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(_channel!);
      await androidPlugin.requestNotificationsPermission();
    }

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen(_showForegroundNotification);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpen);

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _handleMessageOpen(initialMessage);
    }
  }

  void _handleMessageOpen(RemoteMessage message) {
    final link = message.data['link']?.toString();
    if (link == null || link.isEmpty) return;
    _handleOpen(link);
  }

  void _handleOpen(String url) {
    if (_openUrl != null) {
      _openUrl!(url);
    } else {
      _pendingUrl = url;
    }
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    final title =
        notification?.title ?? message.data['title']?.toString() ?? kDefaultTitle;
    final body = notification?.body ?? message.data['msg']?.toString() ?? '';
    if (title.isEmpty && body.isEmpty) return;

    final payload = message.data['link']?.toString() ?? '';

    final androidDetails = AndroidNotificationDetails(
      _channel?.id ?? 'carby_default',
      _channel?.name ?? 'Carby Notifications',
      channelDescription: _channel?.description,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await _localNotifications.show(
      message.hashCode,
      title,
      body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: payload,
    );
  }
}
