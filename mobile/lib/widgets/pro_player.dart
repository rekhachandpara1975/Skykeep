import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../app_state.dart';
import '../theme.dart';

const playbackSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

String clock(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, x = s % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(x)}' : '${two(m)}:${two(x)}';
}

String speedLabel(double v) => '${v == v.roundToDouble() ? v.toInt() : v}x';

/// Seeks by dragging: the full width of the screen is [dragSecondsPerWidth] seconds, like MX Player / VLC.
const dragSecondsPerWidth = 90.0;

/// Phone-style video player: tap to show controls, swipe sideways to seek, double-tap the sides for ±10 s,
/// swipe up/down on the right for volume (full screen), hold for 2× speed, speed menu, previous/next,
/// full screen. With a trailer it plays the trailer first and then continues into the full video.
class ProPlayer extends StatefulWidget {
  const ProPlayer({
    super.key,
    required this.itemId,
    required this.storageKey,
    this.trailerKey,
    this.trailerOnly = false,
    this.onNext,
    this.onPrevious,
    this.onUpgrade,
    this.title,
  });

  final String itemId;

  /// The key to play (the full video; or the trailer itself when [trailerOnly]).
  final String storageKey;

  /// Played before the full video when the viewer is allowed to watch it.
  final String? trailerKey;

  /// The viewer may only watch the trailer: when it ends they are offered the plans instead of the full video.
  final bool trailerOnly;
  final VoidCallback? onNext, onPrevious, onUpgrade;
  final String? title;

  @override
  State<ProPlayer> createState() => _ProPlayerState();
}

class _ProPlayerState extends State<ProPlayer> with WidgetsBindingObserver {
  VideoPlayerController? _c;
  Timer? _save, _hide;
  final _ui = ValueNotifier<int>(0);
  bool _autoFs = false; // fullscreen entered by rotating the device
  Orientation? _lastOrientation;
  DateTime _suppressAutoUntil = DateTime.fromMillisecondsSinceEpoch(0);

  late final List<String> _keys = [if (widget.trailerKey != null && !widget.trailerOnly) widget.trailerKey!, widget.storageKey];
  int _stage = 0;
  bool _failed = false, _opening = false, _controls = true, _fullscreen = false, _ended = false;
  int _autoRetries = 0;
  double _speed = 1.0, _volume = 1.0;
  Duration? _seekTarget; // while swiping
  String? _hud; // short on-screen message (±10 s, volume, 2x)
  Timer? _hudTimer;

  bool get _onTrailer => widget.trailerKey != null && !widget.trailerOnly && _stage == 0;
  bool get _countsResume => !_onTrailer && !widget.trailerOnly;
  String get _posKey => 'pos_${widget.storageKey}';

  void _set(VoidCallback f) {
    if (!mounted) return;
    setState(f);
    _ui.value++;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _lastOrientation = _deviceOrientation();
      _open();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _save?.cancel();
    _hide?.cancel();
    _hudTimer?.cancel();
    _c?.dispose();
    _ui.dispose();
    if (_fullscreen) _restoreChrome();
    super.dispose();
  }

  // Turning the phone drives fullscreen: rotate to landscape → fullscreen, back to portrait → exit.
  Orientation? _deviceOrientation() {
    if (!mounted) return null;
    final view = View.maybeOf(context);
    if (view == null) return null;
    final s = view.physicalSize;
    if (s.width == 0 || s.height == 0) return null;
    return s.width >= s.height ? Orientation.landscape : Orientation.portrait;
  }

  @override
  void didChangeMetrics() {
    final o = _deviceOrientation();
    if (o == null || o == _lastOrientation) return;
    _lastOrientation = o;
    if (_c == null || !_c!.value.isInitialized) return;
    if (o == Orientation.landscape && !_fullscreen) {
      if (DateTime.now().isBefore(_suppressAutoUntil)) return; // just exited: don't snap back in
      _enterFullscreen(auto: true);
    } else if (o == Orientation.portrait && _fullscreen && _autoFs) {
      _exitFullscreen();
    }
  }

  // ---------------- loading ----------------

  Future<void> _open({bool refresh = false, bool autoPlay = false}) async {
    if (!mounted || _opening) return; // one open at a time: the error listener can fire many times
    _opening = true;
    try {
      await _openOnce(refresh: refresh, autoPlay: autoPlay);
    } finally {
      _opening = false;
    }
  }

  Future<void> _openOnce({required bool refresh, required bool autoPlay}) async {
    final app = AppScope.read(context);
    final key = _keys[_stage];
    if (refresh) app.api.forgetSigned('media', key);
    final url = await app.api.signedUrl('media', key);
    if (!mounted) return;
    if (url == null) return _set(() => _failed = true);
    // a URL refresh continues where we were; a new stage starts at its own saved position (full video) or the start (trailer)
    final resumeAt = Duration(milliseconds: refresh && _c != null ? _c!.value.position.inMilliseconds
        : (_countsResume ? app.prefs.getInt(_posKey) : null) ?? 0);
    final old = _c;
    final c = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await c.initialize();
      if (resumeAt > Duration.zero && resumeAt < c.value.duration) await c.seekTo(resumeAt);
      if (!mounted) { await c.dispose(); return; }
      await c.setPlaybackSpeed(_speed);
      await c.setVolume(_volume);
      c.addListener(() => _onTick(c));
      _set(() { _c = c; _failed = false; _ended = false; });
      await old?.dispose();
      _save ??= Timer.periodic(const Duration(seconds: 5), (_) {
        final p = _c?.value.position;
        if (p != null && _countsResume) app.prefs.setInt(_posKey, p.inMilliseconds);
      });
      if (autoPlay) { await c.play(); _scheduleHide(); }
    } catch (_) {
      await c.dispose();
      if (mounted) _set(() => _failed = true);
    }
  }

  void _onTick(VideoPlayerController c) {
    if (!mounted || c != _c) return;
    final v = c.value;
    // signed URL expired mid-stream → refresh and continue (a few times, then show Retry)
    if (v.hasError) {
      if (_autoRetries++ < 3) { _open(refresh: true); } else { _set(() => _failed = true); }
      return;
    }
    final done = v.isInitialized && v.duration > Duration.zero && v.position >= v.duration - const Duration(milliseconds: 250) && !v.isPlaying;
    if (done && !_ended) {
      _ended = true;
      if (_onTrailer) {
        _skipTrailer(); // trailer finished → straight into the full video
        return;
      }
      if (_countsResume) AppScope.read(context).prefs.remove(_posKey);
      _controls = true;
    } else if (!done && _ended && v.isPlaying) {
      _ended = false;
    }
    _set(() {});
  }

  Future<void> _skipTrailer() async {
    if (!_onTrailer) return;
    _stage = 1;
    _ended = false;
    await _open(autoPlay: true);
  }

  // ---------------- controls ----------------

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (_c?.value.isPlaying == true) _set(() => _controls = false);
    });
  }

  void _toggleControls() {
    _set(() => _controls = !_controls);
    if (_controls) _scheduleHide();
  }

  void _showHud(String text) {
    _hudTimer?.cancel();
    _set(() => _hud = text);
    _hudTimer = Timer(const Duration(milliseconds: 700), () => _set(() => _hud = null));
  }

  Future<void> _playPause() async {
    final c = _c;
    if (c == null) return;
    if (_ended) {
      await c.seekTo(Duration.zero);
      _ended = false;
    }
    c.value.isPlaying ? await c.pause() : await c.play();
    _set(() => _controls = true);
    _scheduleHide();
  }

  Future<void> _seekBy(int seconds) async {
    final c = _c;
    if (c == null) return;
    final to = _clamp(c.value.position + Duration(seconds: seconds), c.value.duration);
    await c.seekTo(to);
    _showHud('${seconds > 0 ? '+' : '−'}${seconds.abs()}s');
    _scheduleHide();
  }

  Duration _clamp(Duration d, Duration max) => d < Duration.zero ? Duration.zero : (d > max ? max : d);

  Future<void> _setSpeed(double v) async {
    _speed = v;
    await _c?.setPlaybackSpeed(v);
    _showHud(speedLabel(v));
  }

  // ---------------- gestures ----------------

  double _dragStartX = 0, _dragWidth = 1;
  Duration _dragFrom = Duration.zero;
  double _doubleTapX = 0;
  double _speedBeforeHold = 1.0;

  void _dragStart(DragStartDetails d, double width) {
    _dragStartX = d.localPosition.dx;
    _dragWidth = width <= 0 ? 1 : width;
    _dragFrom = _c?.value.position ?? Duration.zero;
  }

  void _dragUpdate(DragUpdateDetails d) {
    final c = _c;
    if (c == null) return;
    final secs = (d.localPosition.dx - _dragStartX) / _dragWidth * dragSecondsPerWidth;
    final to = _clamp(_dragFrom + Duration(milliseconds: (secs * 1000).round()), c.value.duration);
    _set(() => _seekTarget = to);
  }

  Future<void> _dragEnd() async {
    final to = _seekTarget;
    _set(() => _seekTarget = null);
    if (to != null) await _c?.seekTo(to);
  }

  Future<void> _setVolume(double v) async {
    _volume = v.clamp(0.0, 1.0);
    await _c?.setVolume(_volume);
    _showHud('Volume ${(_volume * 100).round()}%');
  }

  Future<void> _doubleTap(double width) async {
    final x = _doubleTapX;
    if (x < width / 3) {
      await _seekBy(-10);
    } else if (x > width * 2 / 3) {
      await _seekBy(10);
    } else {
      await _playPause();
    }
  }

  // ---------------- full screen ----------------

  void _restoreChrome() {
    SystemChrome.setPreferredOrientations(const []);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future<void> _enterFullscreen({bool auto = false}) async {
    if (_fullscreen || _c == null) return;
    _autoFs = auto;
    _set(() => _fullscreen = true);
    // Button: rotate the app to landscape ourselves. Auto: the device already rotated, so just
    // keep both landscape sides allowed so it follows the phone.
    await SystemChrome.setPreferredOrientations(const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (!mounted) return;
    await Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: true,
      pageBuilder: (_, _, _) => Scaffold(
        backgroundColor: Colors.black,
        body: ValueListenableBuilder<int>(valueListenable: _ui, builder: (_, _, _) => _surface(full: true)),
      ),
    ));
    _restoreChrome();
    if (mounted) _set(() { _fullscreen = false; _autoFs = false; });
  }

  Future<void> _exitFullscreen() async {
    // Return to portrait and briefly ignore the sensor, so holding the phone sideways
    // doesn't immediately re-open fullscreen.
    _suppressAutoUntil = DateTime.now().add(const Duration(milliseconds: 1200));
    _lastOrientation = Orientation.portrait;
    await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    if (mounted) Navigator.of(context).pop();
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) SystemChrome.setPreferredOrientations(const []); // let the phone rotate freely again
    });
  }

  // ---------------- UI ----------------

  Widget _round(IconData icon, VoidCallback? onTap, {double size = 30, String? label}) => IconButton(
        tooltip: label,
        iconSize: size,
        color: Colors.white,
        disabledColor: Colors.white30,
        onPressed: onTap,
        icon: Icon(icon),
      );

  Widget _surface({required bool full}) {
    final c = _c!;
    final v = c.value;
    final pos = _seekTarget ?? v.position;
    final dur = v.duration;
    final showControls = _controls || !v.isPlaying || _ended;
    final ar = v.aspectRatio == 0 ? 16 / 9 : v.aspectRatio;

    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        onDoubleTapDown: (d) => _doubleTapX = d.localPosition.dx,
        onDoubleTap: () => _doubleTap(w),
        onHorizontalDragStart: (d) => _dragStart(d, w),
        onHorizontalDragUpdate: _dragUpdate,
        onHorizontalDragEnd: (_) => _dragEnd(),
        onHorizontalDragCancel: _dragEnd,
        onVerticalDragUpdate: full ? (d) { if (d.localPosition.dx > w / 2) _setVolume(_volume - d.delta.dy / 200); } : null,
        onLongPressStart: (_) { _speedBeforeHold = _speed; _setSpeed(2.0); },
        onLongPressEnd: (_) => _setSpeed(_speedBeforeHold),
        child: Stack(fit: StackFit.expand, children: [
          const ColoredBox(color: Colors.black),
          Center(child: AspectRatio(aspectRatio: ar, child: VideoPlayer(c))),
          if (_seekTarget != null)
            _centerText('${clock(_seekTarget!)}  (${_seekTarget! >= v.position ? '+' : '−'}${(_seekTarget! - v.position).inSeconds.abs()}s)')
          else if (_hud != null)
            _centerText(_hud!),
          if (showControls) ...[
            const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x99000000), Color(0x00000000), Color(0x00000000), Color(0xB3000000)],
                stops: [0, .3, .6, 1]))),
            Positioned(top: 4, left: 8, right: 8, child: Row(children: [
              if (full) _round(Icons.arrow_back, _exitFullscreen, size: 24, label: 'Exit full screen'),
              if (_onTrailer)
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: C.gold, borderRadius: BorderRadius.circular(6)),
                    child: const Text('TRAILER', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: Colors.black))),
              if (full && widget.title != null) Expanded(child: Padding(padding: const EdgeInsets.only(left: 8),
                  child: Text(widget.title!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)))) else const Spacer(),
              if (_onTrailer && widget.trailerKey != null)
                TextButton(onPressed: _skipTrailer, child: const Text('Skip trailer ›', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
            ])),
            Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
              _round(Icons.skip_previous_rounded, widget.onPrevious, size: 36, label: 'Previous'),
              _round(Icons.replay_10_rounded, () => _seekBy(-10), size: 34, label: 'Back 10 seconds'),
              Semantics(button: true, label: v.isPlaying ? 'Pause' : 'Play', child: IconButton.filled(
                  iconSize: 42, style: IconButton.styleFrom(backgroundColor: Colors.white24, foregroundColor: Colors.white),
                  onPressed: _playPause, icon: Icon(_ended ? Icons.replay_rounded : (v.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded)))),
              _round(Icons.forward_10_rounded, () => _seekBy(10), size: 34, label: 'Forward 10 seconds'),
              _round(Icons.skip_next_rounded, widget.onNext, size: 36, label: 'Next'),
            ])),
            Positioned(left: 8, right: 4, bottom: 0, child: Row(children: [
              Text(clock(pos), style: const TextStyle(color: Colors.white, fontSize: 12)),
              Expanded(child: SliderTheme(
                data: SliderTheme.of(context).copyWith(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14), activeTrackColor: C.primary, inactiveTrackColor: Colors.white30, thumbColor: Colors.white),
                child: Slider(
                  value: dur.inMilliseconds == 0 ? 0 : pos.inMilliseconds.clamp(0, dur.inMilliseconds).toDouble(),
                  max: dur.inMilliseconds == 0 ? 1 : dur.inMilliseconds.toDouble(),
                  onChangeStart: (_) => _hide?.cancel(),
                  onChanged: (x) => _set(() => _seekTarget = Duration(milliseconds: x.round())),
                  onChangeEnd: (x) async { _set(() => _seekTarget = null); await c.seekTo(Duration(milliseconds: x.round())); _scheduleHide(); },
                ),
              )),
              Text(clock(dur), style: const TextStyle(color: Colors.white, fontSize: 12)),
              PopupMenuButton<double>(
                tooltip: 'Playback speed',
                initialValue: _speed,
                onOpened: () => _hide?.cancel(),
                onSelected: _setSpeed,
                itemBuilder: (_) => [for (final s in playbackSpeeds) PopupMenuItem(value: s, child: Text(speedLabel(s)))],
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    child: Text(speedLabel(_speed), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
              ),
              _round(full ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded, full ? _exitFullscreen : _enterFullscreen, size: 26, label: full ? 'Exit full screen' : 'Full screen'),
            ])),
          ],
          if (widget.trailerOnly && _ended)
            ColoredBox(color: Colors.black87, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.lock, color: C.gold, size: 32),
              const SizedBox(height: 8),
              const Text('Get Premium to watch the full video', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              if (widget.onUpgrade != null) TextButton(onPressed: widget.onUpgrade, child: const Text('See plans')),
              TextButton(onPressed: _playPause, child: const Text('Watch trailer again')),
            ]))),
        ]),
      );
    });
  }

  Widget _centerText(String t) => Center(child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
        child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
      ));

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return AspectRatio(aspectRatio: 16 / 9, child: Center(child: OutlinedButton(
          onPressed: () { _autoRetries = 0; _open(refresh: true); }, child: const Text('Retry video'))));
    }
    final c = _c;
    if (c == null || !c.value.isInitialized) {
      return const AspectRatio(aspectRatio: 16 / 9, child: Center(child: CircularProgressIndicator()));
    }
    final ar = c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: ar < 1 ? 1 : ar, // tall phone videos stay a sensible height inline; full screen shows them whole
        child: _fullscreen ? const ColoredBox(color: Colors.black) : _surface(full: false),
      ),
    );
  }
}
