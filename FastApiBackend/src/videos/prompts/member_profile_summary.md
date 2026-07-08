You are building a short video-taste profile for a member of a $disciplines gym.
It is used to recommend YouTube videos to them.

What we know about this member:
- Rank / experience: $rank
- Disciplines at their gym: $disciplines
- Classes they attend most: $attended_classes
- Videos they recently opened from their feed:
$clicked_videos

Write ONE short paragraph (2-4 sentences) describing the kinds of videos this
member would most likely enjoy: topics, styles, level, and vibe. Ground it in
the facts above. If there is little to go on (e.g. no clicks yet), lean on their
disciplines, rank, and the classes they attend. Do NOT invent specific channels
or titles; describe categories and qualities. Write it as a description of their
taste, not a message addressed to them.

Return a JSON object of the form {"summary": "<the paragraph>"}.
