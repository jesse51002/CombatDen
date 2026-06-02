import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:app_management/core/constants/design_constants.dart';

/// Search input over the theme list. Reports the raw text on every
/// change; the consuming pager owns the debounce.
class ThemeSearchBar extends StatefulWidget {
  const ThemeSearchBar({super.key, required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  State<ThemeSearchBar> createState() => _ThemeSearchBarState();
}

class _ThemeSearchBarState extends State<ThemeSearchBar> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Rebuild when the field empties / fills so the clear chip toggles.
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTextChanged)
      ..dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.paddingSmall,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        border: Border.all(color: DesignConstants.line),
      ),
      child: Row(
        spacing: DesignConstants.spacingMedium,
        children: [
          Icon(
            Symbols.search_sharp,
            weight: DesignConstants.iconWeight,
            color: DesignConstants.text2nd,
            size: DesignConstants.iconSizeMedium,
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              onChanged: widget.onChanged,
              textInputAction: TextInputAction.search,
              style: DesignConstants.p,
              decoration: InputDecoration(
                hintText: 'Search themes',
                hintStyle: DesignConstants.p.copyWith(
                  color: DesignConstants.text3rd,
                ),
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: DesignConstants.spacingMedium,
                ),
              ),
            ),
          ),
          if (_controller.text.isNotEmpty)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _clear,
              child: Icon(
                Symbols.close_sharp,
                weight: DesignConstants.iconWeight,
                color: DesignConstants.text2nd,
                size: DesignConstants.iconSizeMedium,
              ),
            ),
        ],
      ),
    );
  }
}
