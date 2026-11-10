import 'package:flutter/material.dart';

import 'app_palette.dart';

typedef SheetAction<T> = ({T? value, String label, bool destructive});

Future<bool?> showConfirmationSheet(
  BuildContext context, {
  required String title,
  required IconData icon,
  required String confirmLabel,
  String? cancelLabel = 'キャンセル',
  ImageProvider? image,
  String? message,
  Widget? content,
  bool destructive = true,
}) => showActionSheet<bool>(
  context,
  title: title,
  icon: icon,
  image: image,
  message: message,
  content: content,
  actions: [
    (value: true, label: confirmLabel, destructive: destructive),
    if (cancelLabel != null)
      (value: false, label: cancelLabel, destructive: false),
  ],
);

Future<T?> showActionSheet<T>(
  BuildContext context, {
  required List<SheetAction<T>> actions,
  String? title,
  IconData? icon,
  ImageProvider? image,
  String? message,
  Widget? content,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  final hasHeader = title != null || icon != null || image != null;
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    backgroundColor: context.palette.canvas,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    clipBehavior: Clip.antiAlias,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: hasHeader,
    builder: (sheetContext) {
      final colors = sheetContext.palette;
      final actionStyle = TextButton.styleFrom(
        foregroundColor: colors.ink,
        minimumSize: Size(0, hasHeader ? 54 : 64),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: const RoundedRectangleBorder(),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      );
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: hasHeader
                ? EdgeInsets.zero
                : const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (icon != null || image != null)
                  Center(
                    child: image == null
                        ? CircleAvatar(
                            radius: 24,
                            backgroundColor: colors.control,
                            foregroundColor: colors.ink,
                            child: Icon(icon),
                          )
                        : Container(
                            width: 64,
                            height: 64,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: colors.control,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Image(
                              image: image,
                              fit: BoxFit.contain,
                              excludeFromSemantics: true,
                              errorBuilder: (_, _, _) =>
                                  Icon(icon, color: colors.ink),
                            ),
                          ),
                  ),
                if (title != null)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      24,
                      12,
                      24,
                      message == null ? 20 : 8,
                    ),
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (message != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.muted, fontSize: 14),
                    ),
                  ),
                if (content != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                    child: content,
                  ),
                for (final (index, action) in actions.indexed) ...[
                  if (index > 0 ||
                      hasHeader ||
                      message != null ||
                      content != null)
                    Divider(height: 1, color: colors.outline),
                  TextButton(
                    onPressed: () => Navigator.pop(sheetContext, action.value),
                    style: action.destructive
                        ? actionStyle.copyWith(
                            foregroundColor: WidgetStatePropertyAll(
                              colors.danger,
                            ),
                          )
                        : actionStyle,
                    child: Text(action.label),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}
