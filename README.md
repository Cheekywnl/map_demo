# Flutter Mapbox Navigation App

A clean, minimalistic Flutter navigation app built with Mapbox integration, featuring real-time routing, search functionality, and a modern driving app experience.

## 🚀 Features

- **🗺️ Interactive Map**: Clean, minimalistic map interface using Mapbox light-v11 style
- **📍 Real-time Location**: GPS-based current location tracking
- **🔍 Smart Search**: Search for destinations using Mapbox Geocoding API
- **🛣️ Route Planning**: Detailed turn-by-turn navigation with ETA
- **📱 Modern UI**: Material 3 design with smooth animations
- **🎯 Driving App Experience**: Optimized zoom levels and controls for navigation
- **📊 Route Information**: Distance, duration, and ETA display
- **🔄 Smooth Transitions**: Animated map movements and zoom controls

## 🛠️ Tech Stack

- **Framework**: Flutter
- **Maps**: Mapbox (via flutter_map)
- **Location**: Geolocator
- **HTTP**: http package for API calls
- **UI**: Material 3 Design

## 📋 Prerequisites

- Flutter SDK (latest stable version)
- Android Studio / VS Code
- Android device or emulator
- Mapbox access token

## 🔧 Setup Instructions

### 1. Clone the Repository
```bash
git clone https://github.com/yourusername/flutter-mapbox-app.git
cd flutter-mapbox-app
```

### 2. Install Dependencies
```bash
flutter pub get
```

### 3. Configure Mapbox Access Token
1. Get your Mapbox access token from [Mapbox](https://account.mapbox.com/)
2. Replace the access token in `lib/widgets/map_widget.dart`:
   ```dart
   const String accessToken = 'YOUR_MAPBOX_ACCESS_TOKEN_HERE';
   ```

### 4. Android Configuration
The app is already configured for Android with:
- Location permissions
- Internet permissions
- Mapbox integration

### 5. Run the App
```bash
flutter run
```

## 📱 Usage

### Basic Navigation
1. **Launch the app** - It will automatically detect your current location
2. **Search for destination** - Use the search bar to find places
3. **Select destination** - Tap on a search result to set it as destination
4. **View route** - The app will display the optimal route with ETA
5. **Navigate** - Follow the blue route line to your destination

### Map Controls
- **Center Button** - Tap to return to your current location
- **Zoom** - Pinch to zoom in/out or use zoom controls
- **Pan** - Drag to move around the map

## 🏗️ Project Structure

```
lib/
├── main.dart                 # App entry point
├── widgets/
│   ├── map_widget.dart       # Main map interface
│   └── friends_widget.dart   # Friends feature (placeholder)
├── models/                   # Data models
├── services/                 # API services
├── utils/                    # Helper functions
└── screens/                  # App screens
```

## 🔑 API Keys

This app uses the following APIs:
- **Mapbox Maps API** - For map tiles and styles
- **Mapbox Geocoding API** - For location search
- **Mapbox Directions API** - For route planning

## 🚨 Important Notes

- **API Usage**: Be mindful of Mapbox API usage limits
- **Location Permissions**: The app requires location permissions to function
- **Internet Connection**: Requires internet for map tiles and API calls

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Mapbox](https://www.mapbox.com/) for mapping services
- [Flutter](https://flutter.dev/) for the amazing framework
- [flutter_map](https://pub.dev/packages/flutter_map) for map integration

## 📞 Support

If you encounter any issues or have questions, please open an issue on GitHub.

---

**Happy Navigating! 🗺️🚗**
