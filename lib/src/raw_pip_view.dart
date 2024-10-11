import 'dart:async';

import 'package:flutter/material.dart';

import 'constants.dart';

enum PIPViewSize {
  medium,
  small,
}

class RawPIPView extends StatefulWidget {
  final PIPViewCorner initialCorner;
  final double? floatingWidth;
  final double? floatingHeight;
  final bool avoidKeyboard;
  final Widget? topWidget;
  final Widget? bottomWidget;
  // this is exposed because trying to watch onTap event
  // by wrapping the top widget with a gesture detector
  // causes the tap to be lost sometimes because it
  // is competing with the drag
  final void Function()? onTapTopWidget;

  const RawPIPView({
    Key? key,
    this.initialCorner = PIPViewCorner.topRight,
    this.floatingWidth,
    this.floatingHeight,
    this.avoidKeyboard = true,
    this.topWidget,
    this.bottomWidget,
    this.onTapTopWidget,
  }) : super(key: key);

  @override
  RawPIPViewState createState() => RawPIPViewState();
}

class RawPIPViewState extends State<RawPIPView> with TickerProviderStateMixin {
  late final AnimationController _toggleFloatingAnimationController;
  late final AnimationController _dragAnimationController;
  late final AnimationController _scaleAnimationController;
  late Animation<double> _scaleAnimation;

  late PIPViewCorner _corner;
  Offset _dragOffset = Offset.zero;
  var _isDragging = false;
  var _isFloating = false;
  Widget? _bottomWidgetGhost;
  Map<PIPViewCorner, Offset> _offsets = {};

  PIPViewSize _pipViewState = PIPViewSize.small;

  Size? _mediumSize;

  Timer? _inactivityTimer;
  static const Duration inactivityDuration = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _corner = widget.initialCorner;
    _toggleFloatingAnimationController = AnimationController(
      duration: defaultAnimationDuration,
      vsync: this,
    );
    _dragAnimationController = AnimationController(
      duration: defaultAnimationDuration,
      vsync: this,
    );

    _scaleAnimationController = AnimationController(
      duration:
          const Duration(milliseconds: 300), // Duration for the scale animation
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(
        parent: _scaleAnimationController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant RawPIPView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isFloating) {
      if (widget.topWidget == null || widget.bottomWidget == null) {
        _isFloating = false;
        _bottomWidgetGhost = oldWidget.bottomWidget;
        _toggleFloatingAnimationController.reverse().whenCompleteOrCancel(() {
          if (mounted) {
            setState(() => _bottomWidgetGhost = null);
          }
        });
      }
    } else {
      if (widget.topWidget != null && widget.bottomWidget != null) {
        _isFloating = true;
        _toggleFloatingAnimationController.forward();
      }
    }
  }

  void _updateCornersOffsets({
    required Size spaceSize,
    required Size widgetSize,
    required EdgeInsets windowPadding,
  }) {
    _offsets = _calculateOffsets(
      spaceSize: spaceSize,
      widgetSize: widgetSize,
      windowPadding: windowPadding,
    );
  }

  bool _isAnimating() {
    return _toggleFloatingAnimationController.isAnimating ||
        _dragAnimationController.isAnimating;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;
    setState(() {
      _dragOffset = _dragOffset.translate(
        details.delta.dx,
        details.delta.dy,
      );
    });
  }

  void _onPanCancel() {
    if (!_isDragging) return;
    setState(() {
      _dragAnimationController.value = 0;
      _dragOffset = Offset.zero;
      _isDragging = false;
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (!_isDragging) return;

    final nearestCorner = _calculateNearestCorner(
      offset: _dragOffset,
      offsets: _offsets,
    );
    setState(() {
      _corner = nearestCorner;
      _isDragging = false;
    });
    _dragAnimationController.forward().whenCompleteOrCancel(() {
      _dragAnimationController.value = 0;
      _dragOffset = Offset.zero;
    });
  }

  void _onPanStart(DragStartDetails details) {
    if (_isAnimating()) return;
    setState(() {
      _dragOffset = _offsets[_corner]!;
      _isDragging = true;
    });
  }

  void _onSingleTap() {
    if (_pipViewState == PIPViewSize.small) {
      setState(() {
        _pipViewState = PIPViewSize.medium;
      });
      _scaleAnimationController.forward(); // Start the scale-up animation
      _startInactivityTimer(); // Start the inactivity timer
    }
  }

  void _onDoubleTap() {
    if (_pipViewState == PIPViewSize.medium) {
      _scaleAnimationController.reverse(); // Reverse the scale animation
      setState(() {
        _pipViewState = PIPViewSize.small;
      });
    }
    _inactivityTimer?.cancel(); // Cancel the inactivity timer
  }

  void _startInactivityTimer() {
    _inactivityTimer?.cancel(); // Cancel existing timer if any
    _inactivityTimer = Timer(inactivityDuration, () {
      if (mounted) {
        _scaleAnimationController.reverse(); // Reverse the scale animation
        setState(() {
          _pipViewState = PIPViewSize.small; // Minimize to small size
        });
      }
    });
  }

  Size _getWidgetSize(double width, double height) {
    switch (_pipViewState) {
      case PIPViewSize.medium:
        return _mediumSize!;
      case PIPViewSize.small:
      default:
        return Size(width, height);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    var windowPadding = mediaQuery.padding;
    if (widget.avoidKeyboard) {
      windowPadding += mediaQuery.viewInsets;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final bottomWidget = widget.bottomWidget ?? _bottomWidgetGhost;
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        double? floatingWidth = widget.floatingWidth;
        double? floatingHeight = widget.floatingHeight;
        // if (floatingWidth != null && floatingHeight != null) {
        //   if (floatingWidth > floatingHeight) {
        //     floatingWidth = 200.0;
        //     floatingHeight = 100.0;
        //   } else {
        //     floatingWidth = 100.0;
        //     floatingHeight = 200.0;
        //   }
        // } else
        if (floatingWidth == null && floatingHeight != null) {
          floatingWidth = width / height * floatingHeight;
        }
        floatingWidth ??= 100.0;
        if (floatingHeight == null) {
          floatingHeight = height / width * floatingWidth;
        }

        _mediumSize = Size(floatingWidth * 1.5, floatingHeight * 1.5);

        final floatingWidgetSize =
            _getWidgetSize(floatingWidth, floatingHeight);

        final fullWidgetSize = Size(width, height);

        _updateCornersOffsets(
          spaceSize: fullWidgetSize,
          widgetSize: floatingWidgetSize,
          windowPadding: windowPadding,
        );

        final calculatedOffset = _offsets[_corner];

        // BoxFit.cover
        final widthRatio = floatingWidth / width;
        final heightRatio = floatingHeight / height;
        final scaledDownScale = widthRatio > heightRatio
            ? floatingWidgetSize.width / fullWidgetSize.width
            : floatingWidgetSize.height / fullWidgetSize.height;

        return Stack(
          children: <Widget>[
            if (bottomWidget != null) bottomWidget,
            if (widget.topWidget != null)
              AnimatedBuilder(
                animation: Listenable.merge([
                  _toggleFloatingAnimationController,
                  _dragAnimationController,
                ]),
                builder: (context, child) {
                  final animationCurve = CurveTween(
                    curve: Curves.easeInOutQuad,
                  );
                  final dragAnimationValue = animationCurve.transform(
                    _dragAnimationController.value,
                  );
                  final toggleFloatingAnimationValue = animationCurve.transform(
                    _toggleFloatingAnimationController.value,
                  );

                  final floatingOffset = _isDragging
                      ? _dragOffset
                      : Tween<Offset>(
                          begin: _dragOffset,
                          end: calculatedOffset,
                        ).transform(_dragAnimationController.isAnimating
                          ? dragAnimationValue
                          : toggleFloatingAnimationValue);
                  final borderRadius = Tween<double>(
                    begin: 0,
                    end: 10,
                  ).transform(toggleFloatingAnimationValue);
                  final width = Tween<double>(
                    begin: fullWidgetSize.width,
                    end: floatingWidgetSize.width,
                  ).transform(toggleFloatingAnimationValue);
                  final height = Tween<double>(
                    begin: fullWidgetSize.height,
                    end: floatingWidgetSize.height,
                  ).transform(toggleFloatingAnimationValue);
                  final scale = _pipViewState == PIPViewSize.medium
                      ? _scaleAnimation.value
                      : Tween<double>(
                          begin: 1,
                          end: scaledDownScale,
                        ).transform(toggleFloatingAnimationValue);

                  // final scale = _pipViewState == PIPViewState.medium
                  //     ? _scaleAnimation.value
                  //     : 1.0;

                  return Positioned(
                    left: floatingOffset.dx,
                    top: floatingOffset.dy,
                    child: GestureDetector(
                      onPanStart: _isFloating ? _onPanStart : null,
                      onPanUpdate: _isFloating ? _onPanUpdate : null,
                      onPanCancel: _isFloating ? _onPanCancel : null,
                      onPanEnd: _isFloating ? _onPanEnd : null,
                      onTap: _onSingleTap,
                      onDoubleTap: () {
                        _onDoubleTap();
                        if (widget.onTapTopWidget != null) {
                          widget.onTapTopWidget!();
                        }
                      },
                      child: Material(
                        elevation: 10,
                        borderRadius: BorderRadius.circular(borderRadius),
                        child: Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(borderRadius),
                          ),
                          width: width,
                          height: height,
                          child: Transform.scale(
                            scale: scale,
                            child: OverflowBox(
                              maxHeight: fullWidgetSize.height,
                              maxWidth: fullWidgetSize.width,
                              child: child,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
                child: widget.topWidget,
              ),
          ],
        );
      },
    );
  }
}

enum PIPViewCorner {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

class _CornerDistance {
  final PIPViewCorner corner;
  final double distance;

  _CornerDistance({
    required this.corner,
    required this.distance,
  });
}

PIPViewCorner _calculateNearestCorner({
  required Offset offset,
  required Map<PIPViewCorner, Offset> offsets,
}) {
  _CornerDistance calculateDistance(PIPViewCorner corner) {
    final distance = offsets[corner]!
        .translate(
          -offset.dx,
          -offset.dy,
        )
        .distanceSquared;
    return _CornerDistance(
      corner: corner,
      distance: distance,
    );
  }

  final distances = PIPViewCorner.values.map(calculateDistance).toList();

  distances.sort((cd0, cd1) => cd0.distance.compareTo(cd1.distance));

  return distances.first.corner;
}

Map<PIPViewCorner, Offset> _calculateOffsets({
  required Size spaceSize,
  required Size widgetSize,
  required EdgeInsets windowPadding,
}) {
  Offset getOffsetForCorner(PIPViewCorner corner) {
    final spacing = 16;
    final left = spacing + windowPadding.left;
    final top = spacing + windowPadding.top;
    final right =
        spaceSize.width - widgetSize.width - windowPadding.right - spacing;
    final bottom =
        spaceSize.height - widgetSize.height - windowPadding.bottom - spacing;

    switch (corner) {
      case PIPViewCorner.topLeft:
        return Offset(left, top);
      case PIPViewCorner.topRight:
        return Offset(right, top);
      case PIPViewCorner.bottomLeft:
        return Offset(left, bottom);
      case PIPViewCorner.bottomRight:
        return Offset(right, bottom);
      default:
        throw UnimplementedError();
    }
  }

  final corners = PIPViewCorner.values;
  final Map<PIPViewCorner, Offset> offsets = {};
  for (final corner in corners) {
    offsets[corner] = getOffsetForCorner(corner);
  }

  return offsets;
}
