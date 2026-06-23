import 'package:crm/features/member_details/bloc/invoice_poller.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// The post-charge invoice poll is a fixed, dumb schedule: it fires at
/// 5/10/15/30/60s and stops. A new charge mid-window restarts it (so
/// only one sequence ever runs). `fakeAsync` drives virtual time so the
/// 60s window is deterministic and instant.
void main() {
  group('InvoicePoller', () {
    test('fires once at each default beat (5/10/15/30/60s)', () {
      fakeAsync((async) {
        final poller = InvoicePoller();
        var ticks = 0;
        poller.start(() => ticks++);

        expect(ticks, 0);
        async.elapse(const Duration(seconds: 5));
        expect(ticks, 1);
        async.elapse(const Duration(seconds: 5)); // t=10
        expect(ticks, 2);
        async.elapse(const Duration(seconds: 5)); // t=15
        expect(ticks, 3);
        async.elapse(const Duration(seconds: 15)); // t=30
        expect(ticks, 4);
        async.elapse(const Duration(seconds: 30)); // t=60
        expect(ticks, 5);

        // The window is closed — nothing fires afterwards.
        async.elapse(const Duration(seconds: 120));
        expect(ticks, 5);
        poller.cancel();
      });
    });

    test('restarting resets the schedule — no leftover ticks from the '
        'first sequence', () {
      fakeAsync((async) {
        final poller = InvoicePoller();
        var ticks = 0;
        poller.start(() => ticks++);

        async.elapse(const Duration(seconds: 7)); // first 5s beat fired
        expect(ticks, 1);

        // A second charge mid-window restarts the schedule.
        poller.start(() => ticks++);

        // The first sequence's 10s beat (at t=10) is cancelled; only the
        // new sequence's 5s beat (now at t=12) should fire next.
        async.elapse(const Duration(seconds: 4)); // t=11 — nothing
        expect(ticks, 1);
        async.elapse(const Duration(seconds: 1)); // t=12 — new 5s beat
        expect(ticks, 2);
        poller.cancel();
      });
    });

    test('cancel stops all pending ticks', () {
      fakeAsync((async) {
        final poller = InvoicePoller();
        var ticks = 0;
        poller.start(() => ticks++);

        async.elapse(const Duration(seconds: 5));
        expect(ticks, 1);
        poller.cancel();
        async.elapse(const Duration(seconds: 120));
        expect(ticks, 1);
      });
    });

    test('honors an injected schedule', () {
      fakeAsync((async) {
        final poller = InvoicePoller(schedule: const [
          Duration(milliseconds: 10),
          Duration(milliseconds: 20),
        ]);
        var ticks = 0;
        poller.start(() => ticks++);

        async.elapse(const Duration(milliseconds: 10));
        expect(ticks, 1);
        async.elapse(const Duration(milliseconds: 10)); // t=20
        expect(ticks, 2);
        async.elapse(const Duration(seconds: 1));
        expect(ticks, 2);
        poller.cancel();
      });
    });
  });
}
