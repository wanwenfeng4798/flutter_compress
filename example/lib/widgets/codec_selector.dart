import 'package:material_ui/material_ui.dart';
import 'package:flutter_compress_pro/flutter_compress_pro.dart';

import 'ui.dart';

/// Row of codec pills (h264 / h265 — the plugin's supported set).
class CodecSelector extends StatelessWidget {
  const CodecSelector({
    super.key,
    required this.codec,
    required this.busy,
    required this.onChanged,
  });

  final VideoCodec codec;
  final bool busy;
  final ValueChanged<VideoCodec> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final value in VideoCodec.values) ...[
          Expanded(
            child: Pill(
              label: value.name,
              selected: codec == value,
              onTap: busy ? null : () => onChanged(value),
            ),
          ),
          if (value != VideoCodec.values.last) const SizedBox(width: 10),
        ],
      ],
    );
  }
}
