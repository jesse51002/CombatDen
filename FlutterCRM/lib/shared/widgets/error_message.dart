import 'package:flutter/material.dart';
import 'package:crm/core/constants/design_constants.dart';

/// Error message display widget
class ErrorMessage extends StatelessWidget {
  final String message;

  const ErrorMessage({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DesignConstants.badRed.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        border: Border.all(color: DesignConstants.badRed, width: 2),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: DesignConstants.badRed, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: DesignConstants.p.copyWith(color: DesignConstants.badRed),
            ),
          ),
        ],
      ),
    );
  }
}
