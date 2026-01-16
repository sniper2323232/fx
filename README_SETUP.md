# Carby Flutter Setup

1) Run `flutter pub get` in `carby_app`.
2) Android config file: `android/app/google-services.json`.
3) iOS config file: `ios/Runner/GoogleService-Info.plist` (add it to Runner in Xcode).
4) Upload APNs key in Firebase for iOS push.
5) Place Firebase service account at `D:\public_html (4)\ca\service-account.json` for server-side FCM.

Notes:
- Notifications are sent when the site inserts rows into `notifications`.
- The app registers the FCM token via `app_register_token.php`.
