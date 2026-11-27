import 'package:flutter/material.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import 'pwa_kit.dart';

/// Street map background: OpenFreeMap vector tiles (free, no API key, commercial use allowed).
/// "positron" is a grey style, like the PWA map. Attribution is required — keep [MapCredit] on every map.
const _styleUrl = 'https://tiles.openfreemap.org/styles/positron';

class BaseMapLayer extends StatefulWidget {
  const BaseMapLayer({super.key});
  @override
  State<BaseMapLayer> createState() => _BaseMapLayerState();
}

class _BaseMapLayerState extends State<BaseMapLayer> {
  static Style? _style; // loaded once per app run
  int _tries = 0;

  @override
  void initState() {
    super.initState();
    if (_style == null) _load();
  }

  /// Retries with a growing delay, so a map opened without network fills in when it returns.
  Future<void> _load() async {
    try {
      final s = await StyleReader(uri: _styleUrl).read();
      _style = s;
      if (mounted) setState(() {});
    } catch (_) {
      _tries++;
      await Future<void>.delayed(Duration(seconds: (_tries * 5).clamp(5, 60)));
      if (mounted && _style == null) _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _style;
    if (s == null) return const SizedBox.shrink(); // pins still show on the plain background
    return VectorTileLayer(theme: s.theme, sprites: s.sprites, tileProviders: s.providers, maximumZoom: 21);
  }
}

class MapCredit extends StatelessWidget {
  const MapCredit({super.key, this.bottom = 4});
  final double bottom;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.bottomLeft,
        child: Container(
          margin: EdgeInsets.only(left: 4, bottom: bottom),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          color: const Color(0xB3FFFFFF),
          child: Text('OpenFreeMap © OpenMapTiles · OpenStreetMap', style: ts(9, color: const Color(0xFF4B5563))),
        ),
      );
}
