import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:mobile_app/core/design_constants.dart';

/// Search input over the style picker. Reports the raw text on every
/// change; the consuming pager owns the debounce.
class StyleSearchBar extends StatefulWidget {
  const StyleSearchBar({super.key, required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  State<StyleSearchBar> createState() => _StyleSearchBarState();
}

class _StyleSearchBarState extends State<StyleSearchBar> {
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
      padding: EdgeInsets.symmetric(
        horizontal: DesignConstants.paddingSmall,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      ),
      child: Row(
        spacing: DesignConstants.spacingMedium,
        children: [
          Icon(
            Symbols.search_sharp,
            weight: DesignConstants.iconWeight,
            color: DesignConstants.text2nd,
            size: DesignConstants.iconSizeMd,
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              onChanged: widget.onChanged,
              textInputAction: TextInputAction.search,
              style: DesignConstants.p,
              decoration: InputDecoration(
                hintText: 'Search styles',
                hintStyle: DesignConstants.p.copyWith(
                  color: DesignConstants.text3rd,
                ),
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: EdgeInsets.symmetric(
                  vertical: DesignConstants.spacingLarge,
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
                size: DesignConstants.iconSizeMd,
              ),
            ),
        ],
      ),
    );
  }
}
