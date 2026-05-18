import 'package:equatable/equatable.dart';

/// One resolved brand image slot. App-agnostic leaf type.
///
/// [url] is stored exactly as the backend returns it and may be
/// relative; relative→absolute resolution happens at the
/// consumption boundary (the API client / resolver), not here.
class CustomizationImage extends Equatable {
  final String prompt;
  final String url;

  const CustomizationImage({
    required this.prompt,
    required this.url,
  });

  factory CustomizationImage.fromJson(
    Map<String, dynamic> json,
  ) {
    return CustomizationImage(
      prompt: (json['prompt'] as String?) ?? '',
      url: (json['url'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'prompt': prompt,
        'url': url,
      };

  @override
  List<Object?> get props => [prompt, url];
}
