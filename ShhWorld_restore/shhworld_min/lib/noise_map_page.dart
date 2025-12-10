// Şehir arama, nokta ekleme, 1–10 kısa slider, zorunlu yorum,
// daire rengi 1-10 -> yeşil > sarı > turuncu > kırmızı,
// balona tıklayınca yorumları gösterme,
// Mapbox 3B dünya haritası ile etkileşimli görünüm.

import 'dart:math';
import 'dart:ui' show Offset;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:mapbox_gl/mapbox_gl.dart' as mbx;
import 'package:noise_meter/noise_meter.dart';
import 'package:permission_handler/permission_handler.dart';

class NoisePoint {
  final mbx.LatLng pos;
  final int level; // 1–10
  final String note;
  final DateTime at;
  NoisePoint({required this.pos, required this.level, required this.note})
      : at = DateTime.now();
}

class Place {
  final String label;
  final mbx.LatLng center;
  const Place(this.label, this.center);
}

class NoiseMapPage extends StatefulWidget {
  final VoidCallback? onToggleTheme;
  const NoiseMapPage({super.key, this.onToggleTheme});

  @override
  State<NoiseMapPage> createState() => _NoiseMapPageState();
}

class _NoiseMapPageState extends State<NoiseMapPage> {
  final String _mapboxStyle = 'mapbox://styles/mapbox/light-v11';
  final ll.Distance _distance = const ll.Distance();

  mbx.MapboxMapController? _mapController;
  bool _styleReady = false;
  final List<mbx.Symbol> _symbols = [];
  final Map<String, NoisePoint> _symbolToPoint = {};

  // Basit şehir dizini (örnek). İleride arama kutusuyla OS geocoding’e geçeriz.
  final List<Place> _places = const [
    Place('Taşucu', mbx.LatLng(36.322, 33.894)),
    Place('Silifke', mbx.LatLng(36.377, 33.933)),
    Place('Mersin', mbx.LatLng(36.812, 34.641)),
    Place('Adana', mbx.LatLng(37.000, 35.321)),
    Place('Ankara', mbx.LatLng(39.925, 32.836)),
    Place('İstanbul', mbx.LatLng(41.015, 28.979)),
    Place('İzmir', mbx.LatLng(38.423, 27.142)),
  ];

  final TextEditingController _search = TextEditingController();

  mbx.LatLng _center = const mbx.LatLng(36.322, 33.894);
  double _zoom = 12;

  bool _isMeasuring = false;

  // Kaydedilmiş noktalar (şimdilik RAM’de)
  final List<NoisePoint> _points = [];

  // --------- RENK HARİTASI 1..10 ----------
  Color _colorFor(int lvl) {
    // 1-3: yeşil, 4-6: sarı, 7-8: turuncu, 9-10: kırmızı (koyu)
    if (lvl <= 3) return const Color(0xFF1B5E20).withOpacity(0.55);
    if (lvl <= 6) return const Color(0xFFF9A825).withOpacity(0.55);
    if (lvl <= 8) return const Color(0xFFE65100).withOpacity(0.55);
    return const Color(0xFFB71C1C).withOpacity(0.58);
  }

  void _jumpTo(mbx.LatLng c, {double? zoom}) {
    _center = c;
    if (zoom != null) _zoom = zoom;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _mapController == null || !_styleReady) return;
      await _mapController!.animateCamera(
        mbx.CameraUpdate.newCameraPosition(
          mbx.CameraPosition(
            target: _center,
            zoom: _zoom,
            pitch: 45,
            bearing: 0,
          ),
        ),
      );
      setState(() {});
    });
  }

  ll.LatLng _asLL(mbx.LatLng p) => ll.LatLng(p.latitude, p.longitude);

  String _colorString(Color c) {
    final hex = c.value.toRadixString(16).padLeft(8, '0');
    return '#${hex.substring(2)}';
  }

  Future<void> _refreshSymbols() async {
    if (!_styleReady || _mapController == null) return;

    for (final sym in _symbols) {
      await _mapController!.removeSymbol(sym);
    }
    _symbols.clear();
    _symbolToPoint.clear();

    for (final p in _points) {
      final col = _colorFor(p.level);
      final avg = _avgAround(p.pos);
      final sym = await _mapController!.addSymbol(
        mbx.SymbolOptions(
          geometry: p.pos,
          iconImage: 'marker-15',
          iconSize: 1.4,
          iconColor: _colorString(col),
          textField: avg == 0 ? '${p.level}' : avg.toStringAsFixed(1),
          textColor: '#ffffff',
          textHaloColor: '#000000',
          textHaloWidth: 1.4,
          textOffset: const Offset(0, 1.2),
          textSize: 12,
        ),
      );
      _symbols.add(sym);
      _symbolToPoint[sym.id] = p;
    }
  }

  void _handleSymbolTap(mbx.Symbol sym) {
    final p = _symbolToPoint[sym.id];
    if (p != null) _openCommentsFor(p);
  }

  @override
  void initState() {
    super.initState();
    _centerOnUser();
  }

  @override
  void dispose() {
    _search.dispose();
    _mapController?.onSymbolTapped.remove(_handleSymbolTap);
    super.dispose();
  }

  Future<void> _centerOnUser() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    final pos = await Geolocator.getCurrentPosition();
    if (!mounted) return;
    _jumpTo(mbx.LatLng(pos.latitude, pos.longitude), zoom: 16);
  }

  Future<void> _startMeasurement() async {
    if (_isMeasuring) return;

    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mikrofon izni olmadan ölçüm yapılamıyor.')),
      );
      return;
    }

    setState(() => _isMeasuring = true);
    try {
      final meter = NoiseMeter();
      final reading = await meter.noiseStream.first;
      if (!mounted) return;
      setState(() => _isMeasuring = false);
      await _showMeasurementDialog(reading.meanDecibel);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isMeasuring = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ölçüm başlatılamadı: $e')),
      );
    }
  }

  Future<void> _showMeasurementDialog(double db) async {
    final add = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Ölçüm tamamlandı'),
        content: Text(
          'Mevcut gürültü seviyesi: ${db.toStringAsFixed(1)} dB.\nHaritaya eklemek ister misin?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Kapat'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Haritaya ekle'),
          )
        ],
      ),
    );

    if (add == true) {
      await _addMeasurementPoint(db);
    }
  }

  Future<void> _addMeasurementPoint(double db) async {
    final where = await _resolveCurrentPosition();
    final level = _levelFromDb(db);
    await _openAddSheet(
      where,
      initialLevel: level,
      initialNote: 'Otomatik ölçüm: ${db.toStringAsFixed(1)} dB',
    );
  }

  Future<mbx.LatLng> _resolveCurrentPosition() async {
    try {
      final pos = await Geolocator.getCurrentPosition();
      return mbx.LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      return _center;
    }
  }

  int _levelFromDb(double db) {
    final clamped = db.clamp(40.0, 110.0);
    final normalized = (clamped - 40) / 70; // 0..1
    return max(1, min(10, (1 + normalized * 9).round()));
  }

  // En yakın X km içindeki yorumları ver (panel için)
  List<NoisePoint> _nearby({mbx.LatLng? ref, double km = 3}) {
    ref ??= _center;
    return _points
        .where((p) =>
            _distance.as(ll.LengthUnit.Kilometer, _asLL(ref!), _asLL(p.pos)) <=
            km)
        .toList()
      ..sort((a, b) => b.at.compareTo(a.at));
  }

  // Dairenin ortalamasını hesapla (tooltip)
  double _avgAround(mbx.LatLng at, {double km = 0.5}) {
    final list = _points.where((p) =>
        _distance.as(ll.LengthUnit.Kilometer, _asLL(at), _asLL(p.pos)) <= km);
    if (list.isEmpty) return 0;
    final sum = list.map((e) => e.level).reduce((a, b) => a + b);
    return sum / list.length;
  }

  Future<void> _openAddSheet(mbx.LatLng where,
      {int? initialLevel, String? initialNote}) async {
    final res = await showModalBottomSheet<_AddResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddPointSheet(
        pos: where,
        initialLevel: initialLevel,
        initialNote: initialNote,
      ),
    );
    if (res == null) return;
    setState(() {
      _points.add(NoisePoint(pos: where, level: res.level, note: res.note));
    });
    await _refreshSymbols();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Kaydedildi')),
    );
  }

  void _openCommentsFor(NoisePoint p) {
    final around = _nearby(ref: p.pos, km: 0.4);
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 4,
              width: 44,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(8)),
            ),
            Text('Yakın yorumlar (${around.length})',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final x in around)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: _colorFor(x.level),
                  child: Text(x.level.toString(),
                      style: const TextStyle(color: Colors.white)),
                ),
                title: Text(x.note.isEmpty ? '—' : x.note),
                subtitle: Text(
                    '${x.at.toLocal()}  ·  ${x.pos.latitude.toStringAsFixed(5)}, ${x.pos.longitude.toStringAsFixed(5)}'),
              ),
          ],
        ),
      ),
    );
  }

  // ------- YAN PANEL (sol) ----------
  Widget _buildSidePanel() {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 360),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    labelText: 'Yer Ara (şehir/ilçe)',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _doSearch(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _doSearch, child: const Text('Git')),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Tema değiştir',
                onPressed: widget.onToggleTheme,
                icon: const Icon(Icons.dark_mode),
              ),
            ]),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _openAddSheet(_center),
              icon: const Icon(Icons.add_location_alt),
              label: const Text('Nokta Ekle'),
            ),
            const SizedBox(height: 16),
            Text('Haber Akışı (yakında)',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Container(
              height: 140,
              decoration: BoxDecoration(
                border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: const Text('Bölgenizde son eklenen kayıtlar, uyarılar, vb.'),
            ),
            const SizedBox(height: 16),
            Text('Yakın yorumlar', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SizedBox(
              height: 160,
              child: ListView(
                children: _nearby().take(6).map((p) {
                  return ListTile(
                    visualDensity: VisualDensity.compact,
                    leading: CircleAvatar(
                      backgroundColor: _colorFor(p.level),
                      child: Text('${p.level}',
                          style: const TextStyle(color: Colors.white)),
                    ),
                    title: Text(p.note.isEmpty ? '—' : p.note,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                        '${p.at.hour.toString().padLeft(2, '0')}:${p.at.minute.toString().padLeft(2, '0')}'),
                    onTap: () => _openCommentsFor(p),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _doSearch() {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return;
    final hit = _places.firstWhere(
      (p) => p.label.toLowerCase().contains(q),
      orElse: () => _places.first,
    );
    _jumpTo(hit.center, zoom: 12);
    FocusScope.of(context).unfocus();
  }

  // ---------- HARİTA ----------
  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ShhWorld — Gürültü Haritası'),
      ),
      body: Row(
        children: [
          if (isWide) _buildSidePanel(),
          // Harita
          Expanded(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) {},
              child: mbx.MapboxMap(
                styleString: _mapboxStyle,
                tiltGesturesEnabled: true,
                rotateGesturesEnabled: true,
                scrollGesturesEnabled: true,
                zoomGesturesEnabled: true,
                minMaxZoomPreference: const mbx.MinMaxZoomPreference(1, 20),
                compassEnabled: true,
                initialCameraPosition: mbx.CameraPosition(
                  target: _center,
                  zoom: _zoom,
                  pitch: 45,
                ),
                onMapClick: (_, coord) => _openAddSheet(coord),
                onMapCreated: (ctrl) {
                  _mapController = ctrl;
                  ctrl.onSymbolTapped.add(_handleSymbolTap);
                },
                onStyleLoadedCallback: () {
                  _styleReady = true;
                  _jumpTo(_center, zoom: _zoom);
                  _refreshSymbols();
                },
                onCameraIdle: () async {
                  final pos = await _mapController?.getCameraPosition();
                  if (pos != null && mounted) {
                    setState(() {
                      _center = pos.target;
                      _zoom = pos.zoom;
                    });
                  }
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'measure',
            onPressed: _isMeasuring ? null : _startMeasurement,
            label: Text(_isMeasuring ? 'Ölçülüyor…' : 'Ses ölç'),
            icon: const Icon(Icons.mic),
          ),
          if (!isWide) ...[
            const SizedBox(height: 12),
            FloatingActionButton.extended(
              heroTag: 'add-point',
              onPressed: () => _openAddSheet(_center),
              label: const Text('Nokta Ekle'),
              icon: const Icon(Icons.add_location_alt),
            ),
          ],
        ],
      ),
    );
  }
}

// ------------------- NOKTA EKLE SHEET -------------------

class _AddResult {
  final int level;
  final String note;
  _AddResult(this.level, this.note);
}

class _AddPointSheet extends StatefulWidget {
  final mbx.LatLng pos;
  final int? initialLevel;
  final String? initialNote;
  const _AddPointSheet({required this.pos, this.initialLevel, this.initialNote});

  @override
  State<_AddPointSheet> createState() => _AddPointSheetState();
}

class _AddPointSheetState extends State<_AddPointSheet> {
  late int _level;
  late final TextEditingController _note;
  final _form = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _level = widget.initialLevel != null
        ? max(1, min(10, widget.initialLevel!))
        : 5;
    _note = TextEditingController(text: widget.initialNote);
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.my_location, size: 18),
                const SizedBox(width: 6),
                Text(
                  'Seçili: ${widget.pos.latitude.toStringAsFixed(5)}, '
                  '${widget.pos.longitude.toStringAsFixed(5)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                )
              ],
            ),
            const SizedBox(height: 8),
            // Kısa slider
            Row(
              children: [
                Text('Seviye', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(width: 12),
                SizedBox(
                  width: min(260, w - 200),
                  child: Slider(
                    value: _level.toDouble(),
                    divisions: 9,
                    min: 1,
                    max: 10,
                    label: '$_level',
                    onChanged: (v) => setState(() => _level = v.round()),
                  ),
                ),
                CircleAvatar(
                  radius: 14,
                  backgroundColor: _previewColor(_level),
                  child: Text('$_level',
                      style:
                          const TextStyle(color: Colors.white, fontSize: 12)),
                )
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _note,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Yorum (zorunlu)',
                border: OutlineInputBorder(),
                hintText: 'Kısa açıklama…',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Lütfen yorum yazın' : null,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () {
                if (!_form.currentState!.validate()) return;
                Navigator.pop(context, _AddResult(_level, _note.text.trim()));
              },
              icon: const Icon(Icons.save),
              label: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }

  Color _previewColor(int lvl) {
    if (lvl <= 3) return const Color(0xFF1B5E20);
    if (lvl <= 6) return const Color(0xFFF9A825);
    if (lvl <= 8) return const Color(0xFFE65100);
    return const Color(0xFFB71C1C);
  }
}
