import 'dart:js_interop';
import 'dart:ui_web' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_stripe_web/flutter_stripe_web.dart';
import 'package:stripe_js/stripe_api.dart' as js;
import 'package:stripe_js/stripe_js.dart' as js;
import 'package:web/web.dart' as web;

import 'package:crm/core/constants/design_constants.dart';

/// Status snapshot for the three card sub-fields.
class CardSplitStatus {
  final bool numberComplete;
  final bool expiryComplete;
  final bool cvcComplete;
  final String? brand;

  const CardSplitStatus({
    required this.numberComplete,
    required this.expiryComplete,
    required this.cvcComplete,
    this.brand,
  });

  bool get complete =>
      numberComplete && expiryComplete && cvcComplete;
}

/// Three-up Stripe Elements card form: separate Card
/// Number, Expiration, and CVC fields. Mounts the Number
/// element into [WebStripe.element] so the existing
/// `Stripe.instance.createPaymentMethod` flow tokenises
/// the grouped elements.
class StripeCardSplitField extends StatefulWidget {
  final ValueChanged<CardSplitStatus>? onChanged;

  const StripeCardSplitField({super.key, this.onChanged});

  @override
  State<StripeCardSplitField> createState() =>
      _StripeCardSplitFieldState();
}

class _StripeCardSplitFieldState
    extends State<StripeCardSplitField> {
  late final web.HTMLDivElement _numberDiv;
  late final web.HTMLDivElement _expiryDiv;
  late final web.HTMLDivElement _cvcDiv;
  late final String _numberView;
  late final String _expiryView;
  late final String _cvcView;

  js.StripeElements? _elements;
  js.StripeElement? _numberEl;
  js.StripeElement? _expiryEl;
  js.StripeElement? _cvcEl;

  bool _numberComplete = false;
  bool _expiryComplete = false;
  bool _cvcComplete = false;
  String? _brand;

  @override
  void initState() {
    super.initState();
    final id = identityHashCode(this);
    _numberView = 'stripe_card_number_$id';
    _expiryView = 'stripe_card_expiry_$id';
    _cvcView = 'stripe_card_cvc_$id';

    _numberDiv = _buildHostDiv();
    _expiryDiv = _buildHostDiv();
    _cvcDiv = _buildHostDiv();

    ui.platformViewRegistry
        .registerViewFactory(_numberView, (_) => _numberDiv);
    ui.platformViewRegistry
        .registerViewFactory(_expiryView, (_) => _expiryDiv);
    ui.platformViewRegistry
        .registerViewFactory(_cvcView, (_) => _cvcDiv);

    _mountWhenConnected();
  }

  void _mountWhenConnected() {
    if (!mounted) return;
    if (_numberDiv.isConnected &&
        _expiryDiv.isConnected &&
        _cvcDiv.isConnected) {
      _initStripe();
    } else {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _mountWhenConnected());
    }
  }

  void _initStripe() {
    final elements = WebStripe.js.elements(_elementOptions());
    _elements = elements;
    WebStripe.elements = elements;

    final numberEl = elements.create(
      'cardNumber',
      _elementStyle(disableLink: true),
    )..mount(_numberDiv);
    final expiryEl = elements.create(
      'cardExpiry',
      _elementStyle(),
    )..mount(_expiryDiv);
    final cvcEl = elements.create(
      'cardCvc',
      _elementStyle(),
    )..mount(_cvcDiv);

    _numberEl = numberEl;
    _expiryEl = expiryEl;
    _cvcEl = cvcEl;

    WebStripe.element = numberEl;

    js.CardPaymentElement(numberEl).onChange((event) {
      _numberComplete = event.complete;
      _brand = event.brand;
      _emit();
    });
    js.CardPaymentElement(expiryEl).onChange((event) {
      _expiryComplete = event.complete;
      _emit();
    });
    js.CardPaymentElement(cvcEl).onChange((event) {
      _cvcComplete = event.complete;
      _emit();
    });
  }

  void _emit() {
    widget.onChanged?.call(CardSplitStatus(
      numberComplete: _numberComplete,
      expiryComplete: _expiryComplete,
      cvcComplete: _cvcComplete,
      brand: _brand,
    ));
  }

  js.JsElementsCreateOptions _elementOptions() {
    return js.JsElementsCreateOptions(
      appearance: js.ElementAppearance(
        theme: js.ElementTheme.night,
        variables: {
          'colorText': _cssColor(DesignConstants.text),
          'colorBackground': _cssColor(DesignConstants.card),
          'colorPrimary':
              _cssColor(DesignConstants.primaryColor),
          'colorDanger': _cssColor(DesignConstants.badRed),
          'fontSizeBase': '16px',
          'borderRadius':
              '${DesignConstants.radiusBig.toInt()}px',
        },
      ).toJson().jsify() as js.JsElementAppearance,
    );
  }

  JSAny _elementStyle({bool disableLink = false}) {
    return {
      if (disableLink) 'disableLink': true,
      'style': {
        'base': {
          'color': _cssColor(DesignConstants.text),
          'fontSize': '16px',
          '::placeholder': {
            'color': _cssColor(
              _composite(
                DesignConstants.text.withValues(alpha: 0.5),
                DesignConstants.card,
              ),
            ),
          },
        },
        'invalid': {
          'color': _cssColor(DesignConstants.badRed),
        },
      },
    }.jsify() as JSAny;
  }

  web.HTMLDivElement _buildHostDiv() {
    return web.HTMLDivElement()
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.display = 'flex'
      ..style.alignItems = 'center';
  }

  /// Stripe only accepts solid HEX / rgb() / hsl() color
  /// strings. Translucent colors must be composited by the
  /// caller before being passed.
  String _cssColor(Color color) {
    final solid = color.a < 1.0
        ? _composite(color, DesignConstants.card)
        : color;
    final argb = solid.toARGB32();
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    return '#'
        '${r.toRadixString(16).padLeft(2, '0')}'
        '${g.toRadixString(16).padLeft(2, '0')}'
        '${b.toRadixString(16).padLeft(2, '0')}';
  }

  /// Composites [fg] over [bg] (both assumed `sRGB`).
  /// Returns an opaque color approximating the blended
  /// appearance, suitable for APIs that reject rgba().
  Color _composite(Color fg, Color bg) {
    final alpha = fg.a;
    final bgRgb = bg.a < 1.0 ? _composite(bg, Colors.black) : bg;
    final r = fg.r * alpha + bgRgb.r * (1 - alpha);
    final g = fg.g * alpha + bgRgb.g * (1 - alpha);
    final b = fg.b * alpha + bgRgb.b * (1 - alpha);
    return Color.from(alpha: 1.0, red: r, green: g, blue: b);
  }

  @override
  void dispose() {
    _numberEl?.unmount();
    _expiryEl?.unmount();
    _cvcEl?.unmount();
    if (WebStripe.element == _numberEl) {
      WebStripe.element = null;
    }
    if (WebStripe.elements == _elements) {
      WebStripe.elements = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        _LabeledField(
          label: 'Card Number',
          viewType: _numberView,
        ),
        Row(
          spacing: DesignConstants.spacingMedium,
          children: [
            Expanded(
              child: _LabeledField(
                label: 'Expiration',
                viewType: _expiryView,
              ),
            ),
            Expanded(
              child: _LabeledField(
                label: 'CVC',
                viewType: _cvcView,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final String viewType;

  const _LabeledField({
    required this.label,
    required this.viewType,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text(
          label,
          style: DesignConstants.h3.copyWith(
            color: DesignConstants.text,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignConstants.spacingMedium,
            vertical: 14,
          ),
          decoration: BoxDecoration(
            color: DesignConstants.card,
            borderRadius: BorderRadius.circular(
              DesignConstants.radiusBig,
            ),
            border: Border.all(
              color: DesignConstants.text,
              width: 2,
            ),
          ),
          child: SizedBox(
            height: 20,
            child: HtmlElementView(viewType: viewType),
          ),
        ),
      ],
    );
  }
}
