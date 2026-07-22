import 'package:flutter/material.dart';
import 'package:graphview/GraphView.dart';

import '../models/vuln_models.dart';
import '../theme/app_theme.dart';

/// Interactive 2D force-directed vulnerability graph -- native-Flutter
/// counterpart to VulnGraph2D.tsx/VulnGraph3D.tsx's Mermaid/three.js views
/// on the web app. Deliberately 2D-only here (no WebView dependency): same
/// underlying GraphData, same node-type/severity coloring, so nothing about
/// the *data* is lost, only the "spin it around in 3D" presentation --
/// tap a node to see the same detail info the web app's drawer shows.
class VulnGraph2DView extends StatefulWidget {
  final GraphData graph;
  final void Function(GraphNode node)? onNodeTap;

  const VulnGraph2DView({super.key, required this.graph, this.onNodeTap});

  @override
  State<VulnGraph2DView> createState() => _VulnGraph2DViewState();
}

class _VulnGraph2DViewState extends State<VulnGraph2DView> {
  late Graph _graph;
  late FruchtermanReingoldAlgorithm _algorithm;
  final TransformationController _transform = TransformationController();

  static const double _minScale = 0.05;
  static const double _maxScale = 4;
  double _scale = 1;

  @override
  void initState() {
    super.initState();
    _build();
    _transform.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransformChanged);
    _transform.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final newScale = _transform.value.getMaxScaleOnAxis();
    if ((newScale - _scale).abs() > 0.001) {
      setState(() => _scale = newScale);
    }
  }

  void _setScale(double next) {
    final current = _transform.value.getMaxScaleOnAxis();
    if (current <= 0) return;
    final factor = next / current;
    _transform.value = _transform.value.clone()..scale(factor);
  }

  @override
  void didUpdateWidget(covariant VulnGraph2DView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.graph != widget.graph) _build();
  }

  void _build() {
    _graph = Graph()..isTree = false;
    if (widget.graph.nodes.isEmpty) return;

    final nodesById = <String, Node>{};
    for (final n in widget.graph.nodes) {
      nodesById[n.id] = Node.Id(n.id);
    }
    for (final n in widget.graph.nodes) {
      _graph.addNode(nodesById[n.id]!);
    }
    for (final link in widget.graph.links) {
      final from = nodesById[link.source];
      final to = nodesById[link.target];
      if (from != null && to != null) {
        _graph.addEdge(from, to, paint: Paint()..color = Colors.grey.withValues(alpha: 0.5));
      }
    }
    _algorithm = FruchtermanReingoldAlgorithm(FruchtermanReingoldConfiguration()..iterations = 400);
  }

  GraphNode? _nodeData(String id) {
    for (final n in widget.graph.nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.graph.nodes.isEmpty) {
      return Center(
        child: Text('No graph data available.', style: TextStyle(color: Theme.of(context).appColors.muted)),
      );
    }
    return Stack(
      children: [
        InteractiveViewer(
          transformationController: _transform,
          constrained: false,
          boundaryMargin: const EdgeInsets.all(200),
          minScale: _minScale,
          maxScale: _maxScale,
          child: GraphView(
            graph: _graph,
            algorithm: _algorithm,
            builder: (Node node) {
              final id = node.key!.value as String;
              final data = _nodeData(id);
              return _NodeChip(data: data, onTap: data == null ? null : () => widget.onNodeTap?.call(data));
            },
          ),
        ),
        Positioned(
          right: 12,
          bottom: 12,
          child: _ZoomControls(
            scale: _scale,
            minScale: _minScale,
            maxScale: _maxScale,
            onChanged: _setScale,
            onReset: () => _transform.value = Matrix4.identity(),
          ),
        ),
      ],
    );
  }
}

class _ZoomControls extends StatelessWidget {
  final double scale;
  final double minScale;
  final double maxScale;
  final ValueChanged<double> onChanged;
  final VoidCallback onReset;

  const _ZoomControls({
    required this.scale,
    required this.minScale,
    required this.maxScale,
    required this.onChanged,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(24),
      color: Theme.of(context).cardColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.remove, size: 18),
              tooltip: 'Zoom out',
              onPressed: () => onChanged((scale - 0.25).clamp(minScale, maxScale)),
            ),
            SizedBox(
              width: 120,
              child: Slider(
                value: scale.clamp(minScale, maxScale),
                min: minScale,
                max: maxScale,
                onChanged: onChanged,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add, size: 18),
              tooltip: 'Zoom in',
              onPressed: () => onChanged((scale + 0.25).clamp(minScale, maxScale)),
            ),
            IconButton(
              icon: const Icon(Icons.center_focus_strong, size: 18),
              tooltip: 'Reset zoom',
              onPressed: onReset,
            ),
          ],
        ),
      ),
    );
  }
}

class _NodeChip extends StatelessWidget {
  final GraphNode? data;
  final VoidCallback? onTap;
  const _NodeChip({required this.data, required this.onTap});

  Color _color() {
    if (data == null) return Colors.grey;
    if (data!.type == 'cve' || data!.type == 'finding') {
      return SeverityColors.forSeverity(data!.severity ?? 'UNKNOWN');
    }
    switch (data!.type) {
      case 'package':
      case 'technology':
        return const Color(0xFF3B82F6);
      case 'cwe':
      case 'category':
        return const Color(0xFFA855F7);
      case 'fix':
        return const Color(0xFF22C55E);
      case 'site':
        return const Color(0xFFE2E8F0);
      default:
        return const Color(0xFF94A3B8);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color();
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withValues(alpha: 0.2)),
        ),
        child: Text(
          data?.label ?? '',
          style: const TextStyle(fontSize: 11, color: Colors.black, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
