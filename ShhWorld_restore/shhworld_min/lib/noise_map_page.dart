// Şehir arama, nokta ekleme, 1–10 kısa slider, zorunlu yorum,
// daire rengi 1-10 -> yeşil > sarı > turuncu > kırmızı,
// balona tıklayınca yorumları gösterme,
// MapController post-frame ile (kırmızı hata çözümü).

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class NoisePoint {
  final LatLng pos;
  final int level; // 1–10
  final String note;
  final DateTime at;
  NoisePoint({required this.pos, required this.level, required this.note})
      : at = DateTime.now();
}

class Place {
  final String label;
  final LatLng center;
  const Place(this.label, this.center);
}

class NoiseMapPage extends StatefulWidget {
  final VoidCallback? onToggleTheme;
  const NoiseMapPage({super.key, this.onToggleTheme});

  @override
  State<NoiseMapPage> createState() => _NoiseMapPageState();
}

class _NoiseMapPageState extends State<NoiseMapPage> {
  final MapController _map = MapController();

  // Basit şehir dizini (örnek). İleride arama kutusuyla OS geocoding’e geçeriz.
  final List<Place> _places = const [
    Place('Taşucu', LatLng(36.322, 33.894)),
    Place('Silifke', LatLng(36.377, 33.933)),
    Place('Mersin', LatLng(36.812, 34.641)),
    Place('Adana', LatLng(37.000, 35.321)),
    Place('Ankara', LatLng(39.925, 32.836)),
    Place('İstanbul', LatLng(41.015, 28.979)),
    Place('İzmir', LatLng(38.423, 27.142)),
  ];

  final TextEditingController _search = TextEditingController();

  LatLng _center = const LatLng(36.322, 33.894);
  double _zoom = 12;

  // Kaydedilmiş noktalar (şimdilik RAM’de)
  final List<NoisePoint> _points = [];

  // --------- RENK HARİTASI 1..10 ----------
  Color _colorFor(int lvl) {
    // 1-3: yeşil, 4-5: sarı, 6-7: turuncu, 8-10: kırmızı (koyu)
    if (lvl <= 3) return const Color(0xFF1B5E20).withOpacity(0.55);
    if (lvl <= 5) return const Color(0xFFF9A825).withOpacity(0.55);
    if (lvl <= 7) return const Color(0xFFE65100).withOpacity(0.55);
    return const Color(0xFFB71C1C).withOpacity(0.58);
  }

  // ---------- HATA ÇÖZÜMÜ: move’u post-frame’te çağır ----------
  void _jumpTo(LatLng c, {double? zoom}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _center = c;
      if (zoom != null) _zoom = zoom;
      if (!mounted) return;
      _map.move(_center, _zoom);
      setState(() {});
    });
  }

  @override
  void initState() {
    super.initState();
    _jumpTo(_center, zoom: 12);
  }

  // En yakın X km içindeki yorumları ver (panel için)
  List<NoisePoint> _nearby({LatLng? ref, double km = 3}) {
    ref ??= _center;
    const d = Distance();
    return _points
        .where((p) => d.as(LengthUnit.Kilometer, ref!, p.pos) <= km)
        .toList()
      ..sort((a, b) => b.at.compareTo(a.at));
  }

  // Dairenin ortalamasını hesapla (tooltip)
  double _avgAround(LatLng at, {double km = 0.5}) {
    const d = Distance();
    final list =
        _points.where((p) => d.as(LengthUnit.Kilometer, at, p.pos) <= km);
    if (list.isEmpty) return 0;
    final sum = list.map((e) => e.level).reduce((a, b) => a + b);
    return sum / list.length;
  }

  Future<void> _openAddSheet(LatLng where) async {
    final res = await showModalBottomSheet<_AddResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddPointSheet(pos: where),
    );
    if (res == null) return;
    setState(() {
      _points.add(NoisePoint(pos: where, level: res.level, note: res.note));
    });
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
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text(
                      'Not: Android/iOS’ta mikrofonu açarak bulunduğun yerdeki dB ölçümünü otomatik alabileceğiz. Web/Windows’ta işaretle.'),
                ));
              },
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
              onPointerDown: (_) {}, // web için scroll/gesture stabil
              child: FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCenter: _center,
                  initialZoom: _zoom,
                  onTap: (tapPos, latLng) => _openAddSheet(latLng),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                    subdomains: const ['a', 'b', 'c'],
                    userAgentPackageName: 'com.shhworld.app',
                  ),
                  // MarkerLayer (tıklanabilir daire)
                  MarkerLayer(
                    markers: _points.map((p) {
                      final col = _colorFor(p.level);
                      final avg = _avgAround(p.pos);
                      final size = max(60.0, 40 + p.level * 14.0);
                      return Marker(
                        point: p.pos,
                        width: size,
                        height: size,
                        alignment: Alignment.center,
                        child: GestureDetector(
                          onTap: () => _openCommentsFor(p),
                          child: Container(
                            decoration: BoxDecoration(
                              color: col,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: col.withOpacity(0.25),
                                  blurRadius: 16,
                                )
                              ],
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              avg == 0 ? '${p.level}' : avg.toStringAsFixed(1),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: !isWide
          ? FloatingActionButton.extended(
              onPressed: () => _openAddSheet(_center),
              label: const Text('Nokta Ekle'),
              icon: const Icon(Icons.add_location_alt),
            )
          : null,
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
  final LatLng pos;
  const _AddPointSheet({required this.pos});

  @override
  State<_AddPointSheet> createState() => _AddPointSheetState();
}

class _AddPointSheetState extends State<_AddPointSheet> {
  int _level = 5;
  final _note = TextEditingController();
  final _form = GlobalKey<FormState>();

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
    if (lvl <= 5) return const Color(0xFFF9A825);
    if (lvl <= 7) return const Color(0xFFE65100);
    return const Color(0xFFB71C1C);
  }
}
