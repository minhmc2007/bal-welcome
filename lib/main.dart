import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ffi' hide Size;
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:animate_do/animate_do.dart';
import 'package:window_manager/window_manager.dart';

// ==========================================
// SYSTEM & ONE-TIME RUN LOGIC
// ==========================================

enum SystemMode { liveIso, installed, unknown }

/// Checks if we are in the Arch ISO Live Environment
bool _isLiveEnv() {
  return Directory('/run/archiso/bootmnt').existsSync();
}

/// Checks if the system is fully installed (system-wide marker)
bool _isInstalled() {
  return File('/etc/bal-installed').existsSync();
}

/// Determines current system state
SystemMode getSystemMode() {
  if (_isInstalled()) return SystemMode.installed;
  if (_isLiveEnv()) return SystemMode.liveIso;
  return SystemMode.unknown;
}

/// 1. Checks for Session Lock (Prevent opening app twice in same session)
/// 2. Checks for First-Run Lock (If installed, prevent running ever again)
Future<void> performStartupChecks() async {
  final mode = getSystemMode();
  final String? home = Platform.environment['HOME'];

  // A. SESSION LOCK (Prevents double-clicking icon)
  // ------------------------------------------------
  final sessionLock = File('/tmp/bal_welcome_session.lock');
  if (await sessionLock.exists()) {
    // App is already running in this session. Exit silently.
    exit(0);
  }
  try {
    await sessionLock.create();
    // Clean up lock when app closes naturally (optional, but good practice)
    ProcessSignal.sigterm.watch().listen((_) => sessionLock.deleteSync());
  } catch (e) {
    debugPrint("Warning: Could not create session lock: $e");
  }

  // B. PERSISTENT LOCK (Strict "Run Once" for Installed System)
  // ------------------------------------------------
  // If we are installed, we only want to run this app ONE TIME ever.
  if (mode == SystemMode.installed && home != null) {
    final firstRunMarker = File('$home/.config/bal-welcome-done');

    if (await firstRunMarker.exists()) {
      debugPrint("System is installed and Welcome App has run before.");
      debugPrint("Exiting to prevent re-run.");
      exit(0);
    }
  }
}

/// Creates the persistent marker so the app doesn't run again on next boot
Future<void> markSetupAsComplete() async {
  final String? home = Platform.environment['HOME'];
  if (home != null) {
    try {
      final configDir = Directory('$home/.config');
      if (!await configDir.exists()) {
        await configDir.create(recursive: true);
      }
      // Create the empty file acting as a flag
      await File('$home/.config/bal-welcome-done').create();
      debugPrint("Setup marked as complete. App will not open again.");
    } catch (e) {
      debugPrint("Failed to mark setup complete: $e");
    }
  }
}

// ==========================================
// LINUX LOCALE FIX
// ==========================================
void fixLinuxLocale() {
  if (!Platform.isLinux) return;
  try {
    final libc = DynamicLibrary.open('libc.so.6');
    final setlocale = libc.lookupFunction<
    Pointer<Utf8> Function(Int32, Pointer<Utf8>),
    Pointer<Utf8> Function(int, Pointer<Utf8>)
    >('setlocale');
    final cString = 'C'.toNativeUtf8();
    setlocale(1, cString);
  } catch (e) {
    debugPrint("Failed to set locale: $e");
  }
}

Future<void> main() async {
  // Run checks BEFORE UI init. If check fails (already run), app exits here.
  await performStartupChecks();
  fixLinuxLocale();

  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1280, 720),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setFullScreen(true);
  });

  runApp(const BlueArchiveLinuxApp());
}

class AppTheme {
  static const Color primaryBlue = Color(0xFF128CFF);
  static const Color cyanAccent = Color(0xFF00E5FF);
  static const Color darkText = Color(0xFF2D3436);
  static const Color warningRed = Color(0xFFFF4757);
  static const Color successGreen = Color(0xFF00B894);
}

class BlueArchiveLinuxApp extends StatelessWidget {
  const BlueArchiveLinuxApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Blue Archive Linux',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.black,
        textTheme: GoogleFonts.rubikTextTheme(),
        iconTheme: const IconThemeData(color: AppTheme.primaryBlue),
      ),
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late final Player _player;
  late final VideoController _controller;

  bool _isLoading = false;
  bool _showInfoScreen = false;
  late SystemMode _currentMode;

  @override
  void initState() {
    super.initState();
    _currentMode = getSystemMode();

    _player = Player();
    _controller = VideoController(_player);
    _player.open(Media('asset:///assets/video/bg_loop.mp4'));
    _player.setPlaylistMode(PlaylistMode.loop);
    _player.setVolume(0.0);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  /// Theme generation logic (Main.sh)
  Future<void> _processThemeAndWallpaper() async {
    setState(() => _isLoading = true);

    try {
      final dir = Directory('/usr/share/backgrounds');
      if (await dir.exists()) {
        final files = dir.listSync().where((file) {
          final path = file.path.toLowerCase();
          return path.endsWith('.png') || path.endsWith('.jpg') || path.endsWith('.jpeg');
        }).toList();

        if (files.isNotEmpty) {
          final randomFile = files[Random().nextInt(files.length)];
          final String selectedPath = randomFile.path;

          // Apply visually immediately (optional)
          try { await Process.run('plasma-apply-wallpaperimage', [selectedPath]); } catch (_) {}

          final String? home = Platform.environment['HOME'];
          if (home != null) {
            final targetDir = Directory('$home/wallpaper');
            if (!await targetDir.exists()) await targetDir.create(recursive: true);

            // Copy to ~/wallpaper/img.png
            final File sourceFile = File(selectedPath);
            await sourceFile.copy('$home/wallpaper/img.png');

            // Run theme generation script
            await Process.run('bash', ['main.sh'], workingDirectory: targetDir.path);
          }
        }
      }
    } catch (e) {
      debugPrint("Theme Error: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _showInfoScreen = true;
        });
      }
    }
  }

  /// Handles the specific Exit/Launch logic you requested
  Future<void> _handleFinalLaunch() async {
    debugPrint("Final Launch Sequence. Mode: $_currentMode");

    try {
      if (_currentMode == SystemMode.liveIso) {
        // ==========================================
        // SCENARIO 1: LIVE ISO
        // ==========================================
        // Run Calamares in detached mode
        debugPrint("Running: calamares -d");
        await Process.start('calamares', ['-d'], mode: ProcessStartMode.detached);
      }
      else if (_currentMode == SystemMode.installed) {
        // ==========================================
        // SCENARIO 2: INSTALLED SYSTEM
        // ==========================================
        // 1. Mark as Done (So app never runs again)
        await markSetupAsComplete();

        // 2. Run bal-helper
        debugPrint("Running: bal-helper");
        await Process.start('bal-helper', [], mode: ProcessStartMode.detached);
      }
    } catch (e) {
      debugPrint("Error launching external process: $e");
    } finally {
      // Close the Welcome App
      exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget currentChild;
    if (_isLoading) {
      currentChild = const LoadingView(key: ValueKey('Loading'));
    } else if (_showInfoScreen) {
      currentChild = InfoView(
        key: const ValueKey('Info'),
        mode: _currentMode,
        onExit: _handleFinalLaunch
      );
    } else {
      currentChild = WelcomeView(key: const ValueKey('Welcome'), onNext: _processThemeAndWallpaper);
    }

    return Scaffold(
      body: Stack(
        children: [
          SizedBox.expand(
            child: Video(controller: _controller, fit: BoxFit.cover, controls: NoVideoControls),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.95),
                  Colors.white.withOpacity(0.85),
                  Colors.white.withOpacity(0.4),
                ],
                stops: const [0.0, 0.4, 1.0],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 800),
            switchInCurve: Curves.easeInOutQuart,
              switchOutCurve: Curves.easeInOutQuart,
                transitionBuilder: (Widget child, Animation<double> animation) {
                  final offsetAnimation = Tween<Offset>(
                    begin: const Offset(0.2, 0.0),
                    end: Offset.zero,
                  ).animate(animation);
                  return FadeTransition(opacity: animation, child: SlideTransition(position: offsetAnimation, child: child));
                },
                child: currentChild,
          ),
        ],
      ),
    );
  }
}

// ==========================================
// LOADING VIEW
// ==========================================
class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 100.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FadeInDown(
              child: const SizedBox(
                height: 60, width: 60,
                child: CircularProgressIndicator(color: AppTheme.primaryBlue, strokeWidth: 5),
              ),
            ),
            const SizedBox(height: 30),
            FadeInUp(
              delay: const Duration(milliseconds: 200),
              child: Text("CONNECTING...", style: GoogleFonts.rubik(fontSize: 40, fontWeight: FontWeight.bold, color: AppTheme.darkText, letterSpacing: 2)),
            ),
            const SizedBox(height: 10),
            FadeInUp(
              delay: const Duration(milliseconds: 400),
              child: Text("Analyzing visual data & synchronizing theme protocols.", style: GoogleFonts.sourceCodePro(fontSize: 16, color: Colors.grey[700], fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// WELCOME VIEW
// ==========================================
class WelcomeView extends StatefulWidget {
  final VoidCallback onNext;
  const WelcomeView({super.key, required this.onNext});
  @override
  State<WelcomeView> createState() => _WelcomeViewState();
}

class _WelcomeViewState extends State<WelcomeView> {
  final List<String> _greetings = ["Hello", "こんにちは", "Xin chào", "안녕하세요", "Bonjour", "Hallo", "Hola", "你好"];
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      setState(() => _index = (_index + 1) % _greetings.length);
    });
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 100.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 60, height: 6,
              child: FadeInLeft(from: 50, duration: const Duration(milliseconds: 800), child: Container(color: AppTheme.primaryBlue)),
            ),
            const SizedBox(height: 30),
            SizedBox(
              height: 120,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 600),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(opacity: animation, child: SlideTransition(position: Tween<Offset>(begin: const Offset(0.0, 0.1), end: Offset.zero).animate(animation), child: child));
                },
                child: Text(
                  _greetings[_index],
                  key: ValueKey<int>(_index),
                  style: GoogleFonts.montserrat(fontSize: 90, fontWeight: FontWeight.w200, color: AppTheme.darkText, height: 1.0, letterSpacing: -2)
                ),
              ),
            ),
            const SizedBox(height: 10),
            FadeInUp(
              delay: const Duration(milliseconds: 500),
              child: Text("Welcome to Blue Archive Linux", style: GoogleFonts.rubik(fontSize: 28, color: AppTheme.primaryBlue, fontWeight: FontWeight.w700, letterSpacing: 1.5))
            ),
            const SizedBox(height: 60),
            FadeInUp(
              delay: const Duration(milliseconds: 800),
              child: SenseiButton(text: "CONNECT TO SCHALE", onPressed: widget.onNext)
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// INFO VIEW (Dynamic based on Environment)
// ==========================================
class InfoView extends StatelessWidget {
  final VoidCallback onExit;
  final SystemMode mode;

  const InfoView({super.key, required this.onExit, required this.mode});

  @override
  Widget build(BuildContext context) {
    // Dynamic Text Logic
    String title = "System Initialization Complete";
    String subtitle = "Theme synchronized. Thanks for using Blue Archive Linux.";
    String buttonText = "LAUNCH PLASMA";
    Color buttonColor = AppTheme.primaryBlue;

    if (mode == SystemMode.liveIso) {
      subtitle = "Live Environment Detected. You can now install the system.";
      buttonText = "INSTALL SYSTEM"; // Will run calamares
      buttonColor = AppTheme.successGreen;
    } else if (mode == SystemMode.installed) {
      subtitle = "Setup complete. Launching user session helper.";
      buttonText = "FINISH SETUP"; // Will run bal-helper
    }

    return SizedBox.expand(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 100.0, vertical: 100.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ZoomIn(duration: const Duration(milliseconds: 500), child: Icon(Icons.verified_user_outlined, size: 60, color: mode == SystemMode.liveIso ? AppTheme.successGreen : AppTheme.primaryBlue)),
              const SizedBox(height: 20),
              FadeInDown(from: 20, child: Text(title, style: GoogleFonts.rubik(fontSize: 40, fontWeight: FontWeight.bold, color: AppTheme.darkText, height: 1.1))),
              const SizedBox(height: 10),
              FadeInDown(delay: const Duration(milliseconds: 200), from: 20, child: Text(subtitle, style: GoogleFonts.rubik(fontSize: 22, color: Colors.grey[700], fontWeight: FontWeight.w300))),
              const SizedBox(height: 50),
              FadeInRight(
                delay: const Duration(milliseconds: 400),
                child: Container(
                  width: 550,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(color: Colors.red.withOpacity(0.05), border: Border(left: BorderSide(color: AppTheme.warningRed, width: 4))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [const Icon(Icons.error_outline, color: AppTheme.warningRed), const SizedBox(width: 10), Text("SYSTEM NOTICE", style: GoogleFonts.rubik(fontWeight: FontWeight.bold, color: AppTheme.warningRed, letterSpacing: 1))]),
                      const SizedBox(height: 10),
                      Text("The old Debian-based BAL is outdated. Support is now exclusive to this Arch-based architecture.", style: GoogleFonts.rubik(color: Colors.black87, height: 1.5, fontSize: 14)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 40),
              FadeInUp(delay: const Duration(milliseconds: 600), child: Text("Architect: minhmc2007", style: GoogleFonts.sourceCodePro(color: AppTheme.primaryBlue, fontSize: 16))),
              const SizedBox(height: 50),
              FadeInUp(
                delay: const Duration(milliseconds: 800),
                child: SenseiButton(
                  text: buttonText,
                  onPressed: onExit,
                  isPrimary: true,
                  customColor: mode == SystemMode.liveIso ? AppTheme.successGreen : null,
                )
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// BUTTON COMPONENT
// ==========================================
class SenseiButton extends StatefulWidget {
  final String text;
  final VoidCallback onPressed;
  final bool isPrimary;
  final Color? customColor;

  const SenseiButton({super.key, required this.text, required this.onPressed, this.isPrimary = false, this.customColor});

  @override State<SenseiButton> createState() => _SenseiButtonState();
}

class _SenseiButtonState extends State<SenseiButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isHovered = false;

  @override void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(_controller);
  }

  @override Widget build(BuildContext context) {
    final Color mainColor = widget.customColor ?? AppTheme.primaryBlue;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => _controller.forward(),
        onTapUp: (_) { _controller.reverse(); widget.onPressed(); },
        onTapCancel: () => _controller.reverse(),
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 45, vertical: 20),
            decoration: BoxDecoration(
              color: _isHovered ? mainColor : (widget.isPrimary ? mainColor : Colors.white),
              border: Border.all(color: mainColor, width: 2),
              borderRadius: BorderRadius.zero,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.text, style: GoogleFonts.rubik(color: _isHovered ? Colors.white : (widget.isPrimary ? Colors.white : mainColor), fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(width: 15),
                Icon(Icons.arrow_forward, size: 20, color: _isHovered ? Colors.white : (widget.isPrimary ? Colors.white : mainColor))
              ],
            ),
          ),
        ),
      ),
    );
  }
}
