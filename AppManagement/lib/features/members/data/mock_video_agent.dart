/// Canned conversation for the mocked agentic video-edit screen.
///
/// Walks the VideoService video-brief interview (gym facts, broadest to
/// narrowest). Mirrors how the real agent asks: every answer is a
/// multiple-choice / multi-select selection except the gym type, which is
/// free text. The derived descriptions and regenerated searches that
/// follow are rendered from [kMockVideos] so the result stays consistent.
library;

/// One turn in the scripted conversation.
sealed class AgentTurn {
  const AgentTurn();
}

/// A message from the agent (left bubble).
class AgentPrompt extends AgentTurn {
  final String text;
  const AgentPrompt(this.text);
}

/// A free-text answer from the admin (right bubble). Used only for the
/// gym type, which is genuinely open-ended.
class TextAnswer extends AgentTurn {
  final String text;
  const TextAnswer(this.text);
}

/// A selection answer: the options the agent offered, with the admin's
/// picks already chosen. Single- or multi-select.
class ChoiceAnswer extends AgentTurn {
  final List<ChoiceOption> options;
  final bool multiSelect;
  const ChoiceAnswer({required this.options, this.multiSelect = true});
}

class ChoiceOption {
  final String label;
  final bool selected;
  const ChoiceOption(this.label, {this.selected = false});
}

const List<AgentTurn> kMockAgentConversation = [
  AgentPrompt(
    "Let's tune Apex MMA's video feed. I'll ask a few questions about "
    'the gym, then regenerate the content focus and the searches that '
    'fill the feed.',
  ),
  AgentPrompt('What type of gym is it?'),
  TextAnswer(
    'Mixed martial arts: striking, wrestling, and submission grappling, '
    'trained to work together.',
  ),
  AgentPrompt('How would you describe the gym\'s personality?'),
  ChoiceAnswer(
    options: [
      ChoiceOption('Disciplined & competitive', selected: true),
      ChoiceOption('Technical & cerebral', selected: true),
      ChoiceOption('Welcoming & community-first'),
      ChoiceOption('Old-school & hard-nosed'),
    ],
  ),
  AgentPrompt('Who are you training?'),
  ChoiceAnswer(
    options: [
      ChoiceOption('Beginners getting fit'),
      ChoiceOption('Hobbyists who train like fighters', selected: true),
      ChoiceOption('Amateur competitors chasing a fight', selected: true),
      ChoiceOption('Kids & teens'),
    ],
  ),
  AgentPrompt('What does the gym push back on within MMA?'),
  ChoiceAnswer(
    options: [
      ChoiceOption('Street-fight & brawl clips', selected: true),
      ChoiceOption('"Style X is useless" rage-bait', selected: true),
      ChoiceOption('Single-style purism', selected: true),
      ChoiceOption('Blood-and-bruises glorification'),
    ],
  ),
  AgentPrompt('Any channels to prioritize?'),
  ChoiceAnswer(
    options: [
      ChoiceOption('UFC', selected: true),
      ChoiceOption('BJJ Fanatics', selected: true),
      ChoiceOption('ONE Championship'),
      ChoiceOption('No preference'),
    ],
  ),
  AgentPrompt(
    'Got it. Here\'s the updated content focus and the searches I\'ll run '
    'to refill the feed. Approve them and I\'ll refresh everything.',
  ),
];
