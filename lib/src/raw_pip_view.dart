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
  final bool? isInteractive;
  final Widget? topWidget;
  final Widget? bottomWidget;
  final PIPViewSize? pipViewState;

  // this is exposed because trying to watch onTap event
  // by wrapping the top widget with a gesture detector
  // causes the tap to be lost sometimes because it
  // is competing with the drag
  final void Function()? onDoubleTapTopWidget;
  final void Function()? onDragToClose;

  // Notify parent widget when RawPIPView is interactive or not
  final void Function(bool isInteractive)? onInteractionChange;

  final void Function(PIPViewSize size)? onPIPViewSizeChange;

  const RawPIPView({
    Key? key,
    this.initialCorner = PIPViewCorner.topRight,
    this.floatingWidth,
    this.floatingHeight,
    this.avoidKeyboard = true,
    this.isInteractive,
    this.topWidget,
    this.bottomWidget,
    this.pipViewState,
    this.onDoubleTapTopWidget,
    this.onDragToClose,
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
  // late Animation<double> _scaleAnimation;
  late PIPViewSize _pipViewState;

  late PIPViewCorner _corner;
  Offset _dragOffset = Offset.zero;
  var _isDragging = false;
  var _isFloating = false;
  Widget? _bottomWidgetGhost;
  Size? _mediumSize;
  Map<PIPViewCorner, Offset> _offsets = {};
  Map<PIPViewPosition, Offset> _positionOffsets = {};

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
    if (oldWidget.isInteractive != widget.isInteractive) {
      _notifyInteraction(widget.isInteractive ?? false);
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

  // void _updatePositionsOffsets({
  //   required Size spaceSize,
  //   required Size widgetSize,
  //   required EdgeInsets windowPadding,
  //   double snapPadding = 16.0,
  // }) {
  //   _positionOffsets = _calculatePositionOffsets(
  //     spaceSize: spaceSize,
  //     widgetSize: widgetSize,
  //     windowPadding: windowPadding,
  //     snapPadding: snapPadding,
  //   );
  // }

  bool _isAnimating() {
    return _toggleFloatingAnimationController.isAnimating ||
        _dragAnimationController.isAnimating;
  }

  bool _isDragOverCloseButton(Offset globalPosition) {
    final renderBox = context.findRenderObject() as RenderBox;
    final localPosition = renderBox.globalToLocal(globalPosition);

    // Set dimensions to match the button size (and add buffer for user convenience)
    final buttonWidth = 100.0; // Use the button width from the SizedBox
    final buttonHeight = 40.0; // Use the button height from the SizedBox
    final buffer = 20.0; // Buffer to make the hit area slightly larger

    final closeButtonRect = Rect.fromLTWH(
      (renderBox.size.width - buttonWidth) / 2 - buffer,
      renderBox.size.height - buttonHeight - buffer,
      buttonWidth + buffer * 2,
      buttonHeight + buffer * 2,
    );
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
      widget.onDragToClose
          ?.call(); // Call the close function if over Close button
      _isOverCloseButton = false; // Reset the tracking variable
      return; // Skip the rest of the logic
    }

    final nearestCorner = _calculateNearestCorner(
      offset: _dragOffset,
      offsets: _offsets,
    );
    // final nearestPosition = _calculateNearestPosition(
    //   offset: _dragOffset,
    //   offsets: _positionOffsets,
    // );
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
      setState(() {
        _pipViewState = PIPViewSize.full;
      });
      _scaleAnimationController.reverse();
      widget.onPIPViewSizeChange?.call(_pipViewState);
    }
    _inactivityTimer?.cancel(); // Cancel the inactivity timer
  }

  void _startInactivityTimer() {
    _inactivityTimer?.cancel(); // Cancel existing timer if any
    _inactivityTimer = Timer(inactivityDuration, () {
      if (mounted && _pipViewState != PIPViewSize.full) {
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

        // _updatePositionsOffsets(
        //   spaceSize: fullWidgetSize,
        //   widgetSize: floatingWidgetSize,
        //   windowPadding: windowPadding,
        // );

        final calculatedOffset = _offsets[_corner];

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
                      behavior: HitTestBehavior.translucent,
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
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Container(
                    width: 110.0,
                    height: 40.0,
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 15),
                    decoration: BoxDecoration(
                      color: _isOverCloseButton
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.onSecondary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.close,
                          color: _isOverCloseButton ? Colors.white : null,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Close',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: _isOverCloseButton ? Colors.white : null,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                  ),
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

enum PIPViewPosition {
  topLeft,
  bottomLeft,
  topRight,
  bottomRight,
  leftSide,
  rightSide,
}

class _PositionDistance {
  final PIPViewPosition position;
  final double distance;

  _PositionDistance({
    required this.position,
    required this.distance,
  });
}

PIPViewPosition _calculateNearestPosition({
  required Offset offset,
  required Map<PIPViewPosition, Offset> offsets,
}) {
  _PositionDistance calculateDistance(PIPViewPosition position) {
    final distance = offsets[position]!
        .translate(
          -offset.dx,
          -offset.dy,
        )
        .distanceSquared;
    return _PositionDistance(
      position: position,
      distance: distance,
    );
  }

  final distances = PIPViewPosition.values.map(calculateDistance).toList();

  distances.sort((pd0, pd1) => pd0.distance.compareTo(pd1.distance));

  return distances.first.position;
}

Map<PIPViewPosition, Offset> _calculatePositionOffsets({
  required Size spaceSize,
  required Size widgetSize,
  required EdgeInsets windowPadding,
  double snapPadding = 16.0,
}) {
  Offset getOffsetForPosition(PIPViewPosition position, {double? yPosition}) {
    final left = snapPadding + windowPadding.left;
    final top = snapPadding + windowPadding.top;
    final right =
        spaceSize.width - widgetSize.width - windowPadding.right - snapPadding;
    final bottom = spaceSize.height -
        widgetSize.height -
        windowPadding.bottom -
        snapPadding;

    switch (position) {
      case PIPViewPosition.topLeft:
        return Offset(left, top);
      case PIPViewPosition.bottomLeft:
        return Offset(left, bottom);
      case PIPViewPosition.topRight:
        return Offset(right, top);
      case PIPViewPosition.bottomRight:
        return Offset(right, bottom);
      case PIPViewPosition.leftSide:
        return Offset(left, yPosition ?? top);
      case PIPViewPosition.rightSide:
        return Offset(right, yPosition ?? top);
      default:
        throw UnimplementedError();
    }
  }

  final Map<PIPViewPosition, Offset> offsets = {};

  // Snap points for corners
  offsets[PIPViewPosition.topLeft] =
      getOffsetForPosition(PIPViewPosition.topLeft);
  offsets[PIPViewPosition.bottomLeft] =
      getOffsetForPosition(PIPViewPosition.bottomLeft);
  offsets[PIPViewPosition.topRight] =
      getOffsetForPosition(PIPViewPosition.topRight);
  offsets[PIPViewPosition.bottomRight] =
      getOffsetForPosition(PIPViewPosition.bottomRight);

  // Snap points along left and right sides (create evenly spaced offsets along the side)
  const sideSnapPoints = 8;
  final sideStep =
      (spaceSize.height - windowPadding.vertical - 2 * snapPadding) /
          (sideSnapPoints - 1);

  for (int i = 0; i < sideSnapPoints; i++) {
    final yPosition = snapPadding + windowPadding.top + i * sideStep;
    offsets[PIPViewPosition.leftSide] =
        getOffsetForPosition(PIPViewPosition.leftSide, yPosition: yPosition);
    offsets[PIPViewPosition.rightSide] =
        getOffsetForPosition(PIPViewPosition.rightSide, yPosition: yPosition);
  }

  return offsets;
}
