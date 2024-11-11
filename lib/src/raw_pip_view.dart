import 'dart:async';

import 'package:flutter/material.dart';

import 'constants.dart';

enum PIPViewSize {
  full,
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
  final PIPViewSize? pipViewState;

  // this is exposed because trying to watch onTap event
  // by wrapping the top widget with a gesture detector
  // causes the tap to be lost sometimes because it
  // is competing with the drag
  final void Function()? onDoubleTapTopWidget;
  final void Function()? onCloseView;

  // Notify parent widget when RawPIPView is interactive or not
  final void Function(bool isInteractive)? onInteractionChange;

  final void Function(PIPViewSize size)? onPIPViewSizeChange;

  const RawPIPView({
    Key? key,
    this.initialCorner = PIPViewCorner.topRight,
    this.floatingWidth,
    this.floatingHeight,
    this.avoidKeyboard = true,
    this.topWidget,
    this.bottomWidget,
    this.pipViewState,
    this.onDoubleTapTopWidget,
    this.onCloseView,
    this.onInteractionChange,
    this.onPIPViewSizeChange,
  }) : super(key: key);

  @override
  RawPIPViewState createState() => RawPIPViewState();
}

class RawPIPViewState extends State<RawPIPView> with TickerProviderStateMixin {
  late final AnimationController _toggleFloatingAnimationController;
  late final AnimationController _dragAnimationController;
  late final AnimationController _scaleAnimationController;
  late Animation<double> _scaleAnimation;
  late PIPViewSize _pipViewState;

  late PIPViewCorner _corner;
  Offset _dragOffset = Offset.zero;
  var _isDragging = false;
  var _isFloating = false;
  Widget? _bottomWidgetGhost;
  Size? _mediumSize;
  Map<PIPViewCorner, Offset> _offsets = {};

  Timer? _inactivityTimer;
  static const Duration inactivityDuration = Duration(seconds: 5);

  bool _isOverCloseButton = false;

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
    _pipViewState = widget.pipViewState ?? PIPViewSize.full;
  }

  @override
  void didUpdateWidget(covariant RawPIPView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pipViewState != widget.pipViewState) {
      setState(() {
        _pipViewState = widget.pipViewState ?? PIPViewSize.small;
      });
    }
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

  bool _isDragOverCloseButton(Offset globalPosition) {
    final renderBox = context.findRenderObject() as RenderBox;
    final localPosition = renderBox.globalToLocal(globalPosition);
    print("localPosition: $localPosition");
    final closeButtonRect = Rect.fromLTRB(
      (renderBox.size.width / 2),
      renderBox.size.height - 100,
      (renderBox.size.width / 2),
      40,
    );
    print("closeButtonRect: $closeButtonRect");
    return closeButtonRect.contains(localPosition);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;
    setState(() {
      _dragOffset = _dragOffset.translate(
        details.delta.dx,
        details.delta.dy,
      );

      _isOverCloseButton = _isDragOverCloseButton(details.globalPosition);
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

    // Check if drag ended over the Close button
    if (_isOverCloseButton) {
      widget.onCloseView
          ?.call(); // Call the close function if over Close button
      _isOverCloseButton = false; // Reset the tracking variable
      _pipViewState = PIPViewSize.full;
      _scaleAnimationController.reverse(); // Reverse the scale animation
      return; // Skip the rest of the logic
    }

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

      _startInactivityTimer();
    });
  }

  void _onPanStart(DragStartDetails details) {
    if (_isAnimating()) return;
    _inactivityTimer?.cancel();
    setState(() {
      _dragOffset = _offsets[_corner]!;
      _isDragging = true;
    });
  }

  void _onSingleTap() {
    _notifyInteraction(true);
    if (_pipViewState == PIPViewSize.small) {
      setState(() {
        _pipViewState = PIPViewSize.medium;
        widget.onPIPViewSizeChange?.call(_pipViewState);
      });
      _scaleAnimationController.forward(); // Start the scale-up animation
      _startInactivityTimer(); // Start the inactivity timer
    }
  }

  void _onDoubleTap() {
    _notifyInteraction(true);

    if (_pipViewState == PIPViewSize.medium) {
      // setState(() {
      //   _pipViewState = PIPViewSize.small;
      //   widget.onPIPViewSizeChange?.call(_pipViewState);
      // });
      // _scaleAnimationController.reverse(); // Reverse the scale animation
      _scaleAnimationController.reverse().whenComplete(() {
        setState(() {
          _pipViewState = PIPViewSize.small;
        });
        widget.onPIPViewSizeChange?.call(_pipViewState);
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
          widget.onPIPViewSizeChange?.call(_pipViewState);
        });
        _notifyInteraction(false);
      }
    });
  }

  void _notifyInteraction(bool isInteractive) {
    if (widget.onInteractionChange != null) {
      widget.onInteractionChange!(isInteractive);
    }
  }

  Size _getFloatingSize(double width, double height) {
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

        if (floatingWidth == null && floatingHeight != null) {
          floatingWidth = width / height * floatingHeight;
        }
        floatingWidth ??= 100.0;
        if (floatingHeight == null) {
          floatingHeight = height / width * floatingWidth;
        }

        _mediumSize = Size(floatingWidth * 1.3, floatingHeight * 1.3);

        final floatingWidgetSize =
            _getFloatingSize(floatingWidth, floatingHeight);

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
                  _scaleAnimationController,
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

                  // final width = Tween<double>(
                  //   begin: fullWidgetSize.width,
                  //   end: floatingWidgetSize.width,
                  // ).transform(toggleFloatingAnimationValue);
                  // final height = Tween<double>(
                  //   begin: fullWidgetSize.height,
                  //   end: floatingWidgetSize.height,
                  // ).transform(toggleFloatingAnimationValue);
                  // final scale = _pipViewState == PIPViewSize.medium
                  //     ? _scaleAnimation.value
                  //     : Tween<double>(
                  //         begin: 1,
                  //         end: scaledDownScale,
                  //       ).transform(toggleFloatingAnimationValue);
                  double currentWidth, currentHeight;
                  if (_pipViewState == PIPViewSize.medium) {
                    currentWidth = _mediumSize!.width;
                    currentHeight = _mediumSize!.height;
                  } else {
                    currentWidth = Tween<double>(
                      begin: fullWidgetSize.width,
                      end: floatingWidgetSize.width,
                    ).transform(toggleFloatingAnimationValue);
                    currentHeight = Tween<double>(
                      begin: fullWidgetSize.height,
                      end: floatingWidgetSize.height,
                    ).transform(toggleFloatingAnimationValue);
                  }

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
                        if (widget.onDoubleTapTopWidget != null &&
                            _pipViewState == PIPViewSize.medium) {
                          _onDoubleTap();
                          widget.onDoubleTapTopWidget!();
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
                          width: currentWidth,
                          height: currentHeight,
                          child: OverflowBox(
                            maxHeight: fullWidgetSize.height,
                            maxWidth: fullWidgetSize.width,
                            child: child,
                          ),
                          // Transform.scale(
                          //   scale: scale,
                          //   child: OverflowBox(
                          //     maxHeight: fullWidgetSize.height,
                          //     maxWidth: fullWidgetSize.width,
                          //     child: child,
                          //   ),
                          // ),
                        ),
                      ),
                    ),
                  );
                },
                child: widget.topWidget,
              ),
            if (_isDragging)
              Align(
                alignment: Alignment.bottomCenter,
                child: ElevatedButton.icon(
                  icon: Icon(Icons.close),
                  style: ElevatedButton.styleFrom(),
                  onPressed: null,
                  label: const Text('Close'),
                ),
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
