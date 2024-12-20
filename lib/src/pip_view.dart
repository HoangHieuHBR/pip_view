import 'package:flutter/material.dart';

import 'dismiss_keyboard.dart';
import 'raw_pip_view.dart';

class PIPView extends StatefulWidget {
  final PIPViewCorner initialCorner;
  final double? floatingWidth;
  final double? floatingHeight;
  final bool avoidKeyboard;
  final bool? isInteractive;
  final PIPViewSize? pipViewState;

  final void Function()? onDoubletapPIPView;
  final void Function()? onDragToClose;
  final void Function(bool isInteractive)? onInteractionChange;
  final void Function(PIPViewSize size)? onPIPViewSizeChange;

  final Widget Function(
    BuildContext context,
    bool isFloating,
  ) builder;

  const PIPView({
    Key? key,
    required this.builder,
    this.initialCorner = PIPViewCorner.topRight,
    this.floatingWidth,
    this.floatingHeight,
    this.pipViewState,
    this.avoidKeyboard = true,
    this.isInteractive,
    this.onDoubletapPIPView,
    this.onDragToClose,
    this.onInteractionChange,
    this.onPIPViewSizeChange,
  }) : super(key: key);

  @override
  PIPViewState createState() => PIPViewState();

  static PIPViewState? of(BuildContext context) {
    return context.findAncestorStateOfType<PIPViewState>();
  }
}

class PIPViewState extends State<PIPView> with TickerProviderStateMixin {
  Widget? _bottomWidget;

  void present() {
    return presentBelow(SizedBox.shrink());
  }

  void presentBelow(Widget widget) {
    dismissKeyboard(context);
    setState(() => _bottomWidget = widget);
  }

  void stopFloating() {
    dismissKeyboard(context);
    setState(() => _bottomWidget = null);
  }

  @override
  Widget build(BuildContext context) {
    final isFloating = _bottomWidget != null;
    return RawPIPView(
      avoidKeyboard: widget.avoidKeyboard,
      isInteractive: widget.isInteractive,
      pipViewState: widget.pipViewState,
      bottomWidget: isFloating
          ? Navigator(
              onGenerateInitialRoutes: (navigator, initialRoute) => [
                MaterialPageRoute(builder: (context) => _bottomWidget!),
              ],
            )
          : null,
      onDoubleTapTopWidget: !isFloating
          ? null
          : () {
              stopFloating();
              widget.onDoubletapPIPView?.call();
            },
      topWidget: IgnorePointer(
        ignoring: isFloating && widget.pipViewState == PIPViewSize.small,
        child: Builder(
          builder: (context) => widget.builder(context, isFloating),
        ),
      ),
      floatingHeight: widget.floatingHeight,
      floatingWidth: widget.floatingWidth,
      initialCorner: widget.initialCorner,
      onInteractionChange: widget.onInteractionChange,
      onPIPViewSizeChange: widget.onPIPViewSizeChange,
      onDragToClose: () {
        widget.onDragToClose?.call();
      },
    );
  }
}
