/// Which waivers one person still owes for the plan they just picked — the
/// PURE half of a waiver run. The repository reads that answer
/// `satisfiedWaiverIds` and `serverGatedWaiverIds` live in the orchestrator;
/// nothing here is async.
///
/// The already-signed skip FAILS CLOSED and that is a legal invariant, not a
/// nicety: a needless signature costs the member twenty seconds, a MISSING one
/// voids the gym's protection. Only a signature the SERVER positively cleared
/// as at-or-above the re-sign floor ever leaves the queue — an unread, failed
/// or absent answer means ASK.
library;

/// The waivers [planWaiverIds] leaves this person owing, in plan order.
///
/// The queue holds only what they will actually be asked to sign: a waiver the
/// gym already holds a compliant signature for is DROPPED rather than stepped
/// over, so "waiver 2 of 3" counts the signatures they are about to give.
///
/// Two kinds of entry are never dropped — anything the SERVER named at a 422
/// gate ([serverGatedWaiverIds], the backstop that makes a client-side skip
/// safe at all, appended when the plan does not already list it), and anything
/// [satisfiedWaiverIds] did not positively clear.
List<String> waiverQueueFor({
  required List<String> planWaiverIds,
  required Set<String> serverGatedWaiverIds,
  required Set<String> satisfiedWaiverIds,
}) {
  final queue = <String>[
    for (final id in planWaiverIds)
      if (id.trim().isNotEmpty &&
          (serverGatedWaiverIds.contains(id) ||
              !satisfiedWaiverIds.contains(id)))
        id,
  ];
  for (final id in serverGatedWaiverIds) {
    if (!queue.contains(id)) queue.add(id);
  }
  return queue;
}

/// The index of the first entry in [queue] not in [signedWaiverIds], or null
/// when every one of them is done. Signed stays signed: Back then forward
/// never re-asks.
int? firstUnsignedIndex(
  List<String> queue,
  Set<String> signedWaiverIds,
) {
  for (var i = 0; i < queue.length; i++) {
    if (!signedWaiverIds.contains(queue[i])) return i;
  }
  return null;
}
