import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One plotted value with the label that goes under it.
class ChartPoint {
  const ChartPoint({
    required this.value,
    required this.label,
    this.caption,
    this.highlight = false,
  });

  final double value;

  /// Short x-axis label, e.g. `Aug 26`.
  final String label;

  /// Longer text shown when this point is selected.
  final String? caption;

  /// Draws the marker in the warning colour — used for outliers.
  final bool highlight;
}

/// A tappable line chart drawn with [CustomPainter].
///
/// Hand-rolled rather than pulled from a charting package: one fewer
/// dependency to version-solve, and full control over dark mode. See
/// docs/PLAN.md §4.
class SimpleLineChart extends StatefulWidget {
  const SimpleLineChart({
    super.key,
    required this.points,
    required this.formatValue,
    this.overlay,
    this.overlayLabel,
    this.height = 200,
    this.lineColor,
    this.emptyMessage = 'Not enough data yet',
  });

  final List<ChartPoint> points;

  /// Formats a y value for the axis and the selection caption.
  final String Function(double) formatValue;

  /// Optional second line — the rolling average, typically. Must be the same
  /// length as [points] or it is ignored.
  final List<double>? overlay;
  final String? overlayLabel;

  final double height;
  final Color? lineColor;
  final String emptyMessage;

  @override
  State<SimpleLineChart> createState() => _SimpleLineChartState();
}

class _SimpleLineChartState extends State<SimpleLineChart> {
  int? _selected;

  @override
  void didUpdateWidget(SimpleLineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A shorter series must not leave a selection pointing past its end.
    final selected = _selected;
    if (selected != null && selected >= widget.points.length) {
      _selected = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final points = widget.points;

    if (points.length < 2) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Text(
            widget.emptyMessage,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final lineColor = widget.lineColor ?? theme.colorScheme.primary;
    final selected = _selected;
    final overlay = (widget.overlay != null &&
            widget.overlay!.length == points.length)
        ? widget.overlay
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: widget.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => _selectAt(
                  details.localPosition.dx,
                  constraints.maxWidth,
                ),
                onHorizontalDragUpdate: (details) => _selectAt(
                  details.localPosition.dx,
                  constraints.maxWidth,
                ),
                child: CustomPaint(
                  size: Size(constraints.maxWidth, widget.height),
                  painter: _LineChartPainter(
                    points: points,
                    overlay: overlay,
                    selected: selected,
                    lineColor: lineColor,
                    overlayColor: theme.colorScheme.tertiary,
                    gridColor: theme.colorScheme.outlineVariant,
                    labelColor: theme.colorScheme.onSurfaceVariant,
                    highlightColor: theme.colorScheme.error,
                    surfaceColor: theme.colorScheme.surface,
                    formatValue: widget.formatValue,
                    labelStyle: theme.textTheme.labelSmall ??
                        const TextStyle(fontSize: 11),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        _Caption(
          selected: selected == null ? null : points[selected],
          selectedValue: selected == null
              ? null
              : widget.formatValue(points[selected].value),
          overlayLabel: widget.overlayLabel,
          overlayColor: theme.colorScheme.tertiary,
          hasOverlay: overlay != null,
        ),
      ],
    );
  }

  void _selectAt(double dx, double width) {
    final points = widget.points;
    if (points.length < 2) return;

    const leftPad = _LineChartPainter.leftPadding;
    const rightPad = _LineChartPainter.rightPadding;
    final plotWidth = width - leftPad - rightPad;
    if (plotWidth <= 0) return;

    final ratio = ((dx - leftPad) / plotWidth).clamp(0.0, 1.0);
    final index = (ratio * (points.length - 1)).round();
    if (index == _selected) return;
    setState(() => _selected = index);
  }
}

class _Caption extends StatelessWidget {
  const _Caption({
    required this.selected,
    required this.selectedValue,
    required this.overlayLabel,
    required this.overlayColor,
    required this.hasOverlay,
  });

  final ChartPoint? selected;
  final String? selectedValue;
  final String? overlayLabel;
  final Color overlayColor;
  final bool hasOverlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final point = selected;

    if (point == null) {
      return Row(
        children: [
          Expanded(
            child: Text(
              'Tap the chart to inspect a point',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (hasOverlay && overlayLabel != null) ...[
            Container(
              width: 10,
              height: 2,
              color: overlayColor,
            ),
            const SizedBox(width: 6),
            Text(
              overlayLabel!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${point.label} · ${selectedValue ?? ''}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (point.caption != null)
                Text(
                  point.caption!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.points,
    required this.overlay,
    required this.selected,
    required this.lineColor,
    required this.overlayColor,
    required this.gridColor,
    required this.labelColor,
    required this.highlightColor,
    required this.surfaceColor,
    required this.formatValue,
    required this.labelStyle,
  });

  static const double leftPadding = 46;
  static const double rightPadding = 10;
  static const double topPadding = 12;
  static const double bottomPadding = 22;

  final List<ChartPoint> points;
  final List<double>? overlay;
  final int? selected;
  final Color lineColor;
  final Color overlayColor;
  final Color gridColor;
  final Color labelColor;
  final Color highlightColor;
  final Color surfaceColor;
  final String Function(double) formatValue;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final plotWidth = size.width - leftPadding - rightPadding;
    final plotHeight = size.height - topPadding - bottomPadding;
    if (plotWidth <= 0 || plotHeight <= 0) return;

    final values = points.map((p) => p.value).toList();
    var minValue = values.reduce(math.min);
    var maxValue = values.reduce(math.max);

    if (overlay != null && overlay!.isNotEmpty) {
      minValue = math.min(minValue, overlay!.reduce(math.min));
      maxValue = math.max(maxValue, overlay!.reduce(math.max));
    }

    // A flat series would otherwise divide by zero and paint nothing.
    if ((maxValue - minValue).abs() < 1e-9) {
      final pad = maxValue.abs() < 1e-9 ? 1.0 : maxValue.abs() * 0.1;
      minValue -= pad;
      maxValue += pad;
    } else {
      final headroom = (maxValue - minValue) * 0.12;
      minValue -= headroom;
      maxValue += headroom;
    }

    final range = maxValue - minValue;

    double xFor(int index) =>
        leftPadding + (plotWidth * index) / (points.length - 1);
    double yFor(double value) =>
        topPadding + plotHeight * (1 - (value - minValue) / range);

    // --- grid + y labels ---------------------------------------------------
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    const gridLines = 4;
    for (var i = 0; i <= gridLines; i++) {
      final value = minValue + range * (i / gridLines);
      final y = yFor(value);
      canvas.drawLine(
        Offset(leftPadding, y),
        Offset(size.width - rightPadding, y),
        gridPaint,
      );
      _drawText(
        canvas,
        formatValue(value),
        Offset(leftPadding - 6, y),
        align: _TextAlignH.right,
        verticalCenter: true,
      );
    }

    // --- x labels ----------------------------------------------------------
    final labelIndices = <int>{0, points.length - 1};
    if (points.length >= 5) labelIndices.add(points.length ~/ 2);
    if (points.length >= 9) {
      labelIndices.add(points.length ~/ 4);
      labelIndices.add((points.length * 3) ~/ 4);
    }
    for (final index in labelIndices) {
      _drawText(
        canvas,
        points[index].label,
        Offset(xFor(index), size.height - bottomPadding + 4),
        align: index == 0
            ? _TextAlignH.left
            : (index == points.length - 1
                ? _TextAlignH.right
                : _TextAlignH.center),
      );
    }

    // --- filled area -------------------------------------------------------
    final linePath = Path();
    for (var i = 0; i < points.length; i++) {
      final offset = Offset(xFor(i), yFor(points[i].value));
      if (i == 0) {
        linePath.moveTo(offset.dx, offset.dy);
      } else {
        linePath.lineTo(offset.dx, offset.dy);
      }
    }

    final fillPath = Path.from(linePath)
      ..lineTo(xFor(points.length - 1), topPadding + plotHeight)
      ..lineTo(xFor(0), topPadding + plotHeight)
      ..close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            lineColor.withValues(alpha: 0.22),
            lineColor.withValues(alpha: 0.0),
          ],
        ).createShader(
          Rect.fromLTWH(leftPadding, topPadding, plotWidth, plotHeight),
        ),
    );

    // --- overlay line ------------------------------------------------------
    final overlayValues = overlay;
    if (overlayValues != null) {
      final path = Path();
      for (var i = 0; i < overlayValues.length; i++) {
        final offset = Offset(xFor(i), yFor(overlayValues[i]));
        if (i == 0) {
          path.moveTo(offset.dx, offset.dy);
        } else {
          path.lineTo(offset.dx, offset.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = overlayColor.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // --- main line ---------------------------------------------------------
    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // --- markers -----------------------------------------------------------
    // Dense series would turn into a solid band of dots, so only draw them
    // when there is room.
    final drawAll = points.length <= 30;
    for (var i = 0; i < points.length; i++) {
      final isSelected = i == selected;
      if (!drawAll && !isSelected && !points[i].highlight) continue;

      final centre = Offset(xFor(i), yFor(points[i].value));
      final colour = points[i].highlight ? highlightColor : lineColor;

      canvas.drawCircle(centre, isSelected ? 5.5 : 3.2, Paint()..color = surfaceColor);
      canvas.drawCircle(
        centre,
        isSelected ? 5.5 : 3.2,
        Paint()
          ..color = colour
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelected ? 3 : 2,
      );
    }

    // --- selection guide ---------------------------------------------------
    final selectedIndex = selected;
    if (selectedIndex != null &&
        selectedIndex >= 0 &&
        selectedIndex < points.length) {
      final x = xFor(selectedIndex);
      canvas.drawLine(
        Offset(x, topPadding),
        Offset(x, topPadding + plotHeight),
        Paint()
          ..color = lineColor.withValues(alpha: 0.35)
          ..strokeWidth = 1,
      );
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset position, {
    _TextAlignH align = _TextAlignH.left,
    bool verticalCenter = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: labelStyle.copyWith(color: labelColor)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    final dx = switch (align) {
      _TextAlignH.left => position.dx,
      _TextAlignH.center => position.dx - painter.width / 2,
      _TextAlignH.right => position.dx - painter.width,
    };
    final dy = verticalCenter ? position.dy - painter.height / 2 : position.dy;

    painter.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(_LineChartPainter old) =>
      old.points != points ||
      old.overlay != overlay ||
      old.selected != selected ||
      old.lineColor != lineColor ||
      old.gridColor != gridColor;
}

enum _TextAlignH { left, center, right }

/// A simple vertical bar chart, used for monthly spend.
class SimpleBarChart extends StatelessWidget {
  const SimpleBarChart({
    super.key,
    required this.points,
    required this.formatValue,
    this.height = 180,
    this.barColor,
    this.emptyMessage = 'Not enough data yet',
  });

  final List<ChartPoint> points;
  final String Function(double) formatValue;
  final double height;
  final Color? barColor;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (points.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            emptyMessage,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: height,
      child: CustomPaint(
        size: Size.infinite,
        painter: _BarChartPainter(
          points: points,
          barColor: barColor ?? theme.colorScheme.primary,
          gridColor: theme.colorScheme.outlineVariant,
          labelColor: theme.colorScheme.onSurfaceVariant,
          formatValue: formatValue,
          labelStyle:
              theme.textTheme.labelSmall ?? const TextStyle(fontSize: 11),
        ),
      ),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  _BarChartPainter({
    required this.points,
    required this.barColor,
    required this.gridColor,
    required this.labelColor,
    required this.formatValue,
    required this.labelStyle,
  });

  static const double leftPadding = 50;
  static const double rightPadding = 8;
  static const double topPadding = 10;
  static const double bottomPadding = 22;

  final List<ChartPoint> points;
  final Color barColor;
  final Color gridColor;
  final Color labelColor;
  final String Function(double) formatValue;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final plotWidth = size.width - leftPadding - rightPadding;
    final plotHeight = size.height - topPadding - bottomPadding;
    if (plotWidth <= 0 || plotHeight <= 0) return;

    final maxValue = points.map((p) => p.value).reduce(math.max);
    final ceiling = maxValue <= 0 ? 1.0 : maxValue * 1.1;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    const gridLines = 3;
    for (var i = 0; i <= gridLines; i++) {
      final value = ceiling * (i / gridLines);
      final y = topPadding + plotHeight * (1 - i / gridLines);
      canvas.drawLine(
        Offset(leftPadding, y),
        Offset(size.width - rightPadding, y),
        gridPaint,
      );
      _drawText(
        canvas,
        formatValue(value),
        Offset(leftPadding - 6, y),
        alignRight: true,
        verticalCenter: true,
      );
    }

    final slot = plotWidth / points.length;
    final barWidth = math.min(slot * 0.62, 34.0);

    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      final barHeight = plotHeight * (point.value / ceiling);
      final centreX = leftPadding + slot * i + slot / 2;

      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(
          centreX - barWidth / 2,
          topPadding + plotHeight - barHeight,
          barWidth,
          math.max(barHeight, 1),
        ),
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      );

      canvas.drawRRect(rect, Paint()..color = barColor.withValues(alpha: 0.85));
    }

    // Label every bar when there is room, otherwise thin them out.
    final step = slot < 34 ? (34 / slot).ceil() : 1;
    for (var i = 0; i < points.length; i += step) {
      _drawText(
        canvas,
        points[i].label,
        Offset(
          leftPadding + slot * i + slot / 2,
          size.height - bottomPadding + 4,
        ),
        centreHorizontally: true,
      );
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset position, {
    bool alignRight = false,
    bool centreHorizontally = false,
    bool verticalCenter = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: labelStyle.copyWith(color: labelColor)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    var dx = position.dx;
    if (alignRight) dx -= painter.width;
    if (centreHorizontally) dx -= painter.width / 2;
    final dy = verticalCenter ? position.dy - painter.height / 2 : position.dy;

    painter.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(_BarChartPainter old) =>
      old.points != points ||
      old.barColor != barColor ||
      old.gridColor != gridColor;
}
