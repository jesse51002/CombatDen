import 'dart:async';
import 'dart:developer';

import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_base.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_load.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_reads.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_step.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_waiver_plan.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_waiver_task.dart';

/// The waiver run — a REAL step before the money, not a 422 handler.
///
/// The queue is derived from the plans that were picked, so a signature is
/// asked for as part of buying the membership that requires it. The 422 stays
/// the backstop and is authoritative when it fires: anything it names goes
/// back on the queue whatever the client believed.
mixin MembershipWizardWaiverOps on MembershipWizardBase {
  /// Read which waivers each person on the roster has ALREADY signed
  /// compliantly, so the run never re-asks for a signature the gym holds.
  ///
  /// Fired as the plans step opens, not as the waiver step does: the answer
  /// has to be in hand before the first waiver is drawn, or a late read would
  /// re-shape a queue somebody is already looking at. It FAILS CLOSED — a
  /// member whose read did not land keeps every waiver on their queue.
  Future<void> loadSatisfiedWaivers() async {
    final wanted = <String>{
      for (final person in state.people)
        if (!state.satisfiedWaiverIds.containsKey(person.memberId))
          person.memberId,
    };
    if (wanted.isEmpty) return;
    final landed = await gatherSatisfiedWaivers(
      repository: membershipsRepo,
      gymId: state.gymId,
      memberIds: wanted,
    );
    if (isClosed || landed.isEmpty) return;
    emit(
      state.copyWith(
        satisfiedWaiverIds: {...state.satisfiedWaiverIds, ...landed},
      ),
    );
  }

  /// Read the body of the waiver on screen. A failure is an inline retry,
  /// never a dead end.
  @override
  Future<void> loadCurrentWaiver() async {
    final task = state.currentWaiverTask;
    if (task == null) return;
    emit(
      state.copyWith(
        waiver: null,
        waiverLoad: const MembershipWizardLoad.loading(),
      ),
    );
    try {
      final waiver = await membershipsRepo.getWaiver(task.waiverId, state.gymId);
      if (isClosed) return;
      emit(
        state.copyWith(
          waiver: waiver,
          waiverLoad: const MembershipWizardLoad.ready(),
        ),
      );
    } catch (e, st) {
      log('Membership wizard: waiver body read failed',
          error: e, stackTrace: st);
      if (isClosed) return;
      emit(
        state.copyWith(
          waiverLoad: const MembershipWizardLoad.failed(
            'Could not load this waiver.',
          ),
        ),
      );
    }
  }

  /// Re-read the waiver after a failed load or a refused signature.
  Future<void> retryWaiver() => loadCurrentWaiver();

  /// Record one signature and move to the next entry the run still owes.
  ///
  /// The version is echoed and pinned server-side, so a gym that republished
  /// the waiver between the read and this call REFUSES it (409) — nothing is
  /// recorded against text nobody saw, and the body reloads for the new one.
  Future<void> signCurrentWaiver({required String signerName}) async {
    if (state.signing) return;
    final task = state.currentWaiverTask;
    final waiver = state.waiver;
    final versionId = waiver?.currentVersionId;
    final name = signerName.trim();
    if (task == null || waiver == null || versionId == null || name.isEmpty) {
      return;
    }
    emit(state.copyWith(signing: true, waiverStale: false));
    try {
      await membershipsRepo.recordWaiverSignature(
        waiverId: task.waiverId,
        gymId: state.gymId,
        memberId: task.memberId,
        waiverVersionId: versionId,
        signerName: name,
      );
      if (isClosed) return;
      emit(
        state.copyWith(
          signing: false,
          signedWaiverKeys: {...state.signedWaiverKeys, task.key},
          // A signed pair is no longer gated: leaving it on the server list
          // would keep it un-skippable forever.
          serverGate: [
            for (final gated in state.serverGate)
              if (gated.key != task.key) gated,
          ],
          waiver: null,
          waiverLoad: const MembershipWizardLoad.idle(),
        ),
      );
      // Awaited, not fired and forgotten: the caller's `await` should mean
      // "the next waiver is on screen", so nothing can present a Sign button
      // over a body that has not arrived.
      if (state.currentWaiverTask != null) await loadCurrentWaiver();
    } on WaiverStaleVersionException {
      if (isClosed) return;
      emit(state.copyWith(signing: false, waiverStale: true));
      unawaited(loadCurrentWaiver());
    } catch (e, st) {
      log('Membership wizard: waiver signature failed',
          error: e, stackTrace: st);
      if (isClosed) return;
      emit(
        state.copyWith(
          signing: false,
          waiverLoad: const MembershipWizardLoad.failed(
            'Could not record this signature.',
          ),
        ),
      );
    }
  }

  /// Route a 422 back into the run — the backstop.
  ///
  /// The server is authoritative, so anything it names is dropped from this
  /// run's own signed set: leaving the mark would skip the very waiver the
  /// backend blocks on, and the desk would bounce between the money and a step
  /// with nothing left to sign.
  void applyServerWaiverGate(WaiverGateException gate) {
    if (gate.unsigned.isEmpty) return;
    final names = {
      for (final person in state.people) person.memberId: person.name,
    };
    final tasks = <MembershipWizardWaiverTask>[
      for (final item in gate.unsigned)
        MembershipWizardWaiverTask(
          memberId: item.memberId,
          memberName: names[item.memberId] ?? '',
          waiverId: item.waiverId,
          waiverName: item.name,
          serverGated: true,
        ),
    ];
    emit(
      state.copyWith(
        serverGate: tasks,
        signedWaiverKeys: signedMinusGate(state.signedWaiverKeys, tasks),
        step: MembershipWizardStep.waivers,
        waiver: null,
        waiverLoad: const MembershipWizardLoad.idle(),
        waiverStale: false,
        starting: false,
        previewLoad: const MembershipWizardLoad.idle(),
      ),
    );
    unawaited(loadCurrentWaiver());
  }
}
