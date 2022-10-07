import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:uimodel/uimodel.dart';

/// reflected state PDO
class BuiltState {
  int bc = 0;
  int taps = 0;
  bool wasSet = false;
  bool wasEnabled = false;
}

/// This widget should rebuild on changes set as smMask. It counts its rebuilds
/// and reflects state back to TestModel `bs` property.
class BuildsWatcher extends StatelessWidget with UiModelLink {
  final int pos;
  final int smMask;
  final TestModel m;
  final Widget? child;
  BuildsWatcher({
    Key? key,
    required this.m,
    required this.pos,
    required this.smMask,
    this.child,
  }) : super(key: key);
  @override
  Widget build(BuildContext context) {
    // watch also tgLastFlag if disabled, testing dynamic masks (not advised to use)
    m.E[pos] ? watches(m, smMask) : watches(m, smMask | 1 << tgLastFlag);
    final bs = m.bs[pos];
    bs.bc++;
    bs.wasSet = m[pos];
    bs.wasEnabled = m.E[pos];
    return child ?? const SizedBox.shrink();
  }
}

class RegTwice extends StatelessWidget with UiModelLink {
  final TestModel m;
  RegTwice({super.key, required this.m});
  @override
  Widget build(BuildContext context) {
    watches(m, 1);
    watches(m, 1); // should throw
    return const SizedBox.shrink();
  }
}

const tgLastFlag = 5;
const smLastFlag = 1 << 5;

class TestModel with UiModel {
  late final TgIndexed<void> tap;
  final _bs = <BuiltState>[
    // up to 6 our test widgets reflect back their state here
    BuiltState(),
    BuiltState(),
    BuiltState(),
    BuiltState(),
    BuiltState(),
    BuiltState(),
  ];
  TestModel() {
    tap = TgIndexed(((i) {
      _bs[i].taps++;
      tg.toggle(i);
    }), ((i, v) {}));
    tg.notifier = UiNotifier();
  }
  List<BuiltState> get bs => _bs;
}

void main() {
  group('simple', () {
    late TestModel m;
    late BuildsWatcher wtop;
    setUp(() {
      m = TestModel();
      wtop = BuildsWatcher(
          m: m,
          pos: 0,
          smMask: 1,
          child: BuildsWatcher(
              m: m,
              pos: 1,
              smMask: 2,
              child: BuildsWatcher(
                m: m,
                pos: 2,
                smMask: 4,
              )));
    });
    testWidgets('Build at place', (wt) async {
      await wt.pumpWidget(wtop);
      expect(m.bs[0].bc, equals(1)); // initial build should be counted
      expect(m.bs[1].bc, equals(1)); // by all widgets down the tree
      expect(m.bs[2].bc, equals(1)); //
      await wt.pump();
      expect(m.bs[0].bc, equals(1)); // second frame may not build again
      expect(m.bs[1].bc, equals(1));
      expect(m.bs[2].bc, equals(1));
      m.tap[1];
      await wt.pump();
      expect(m.bs[0].bc, equals(1)); // child should NOT rebuild after tap
      expect(m.bs[1].bc, equals(2)); // tapped should rebuild after tap
      expect(m.bs[2].bc, equals(1)); // parent should NOT rebuild after tap
    });
    testWidgets('Offstage build', (wt) async {
      await wt.pumpWidget(Offstage(child: wtop));
      expect(m.bs[0].bc, equals(1)); // initial build should be counted
      expect(m.bs[1].bc, equals(1)); // by all widgets down the tree
      expect(m.bs[2].bc, equals(1)); //
      await wt.pump();
      expect(m.bs[0].bc, equals(1)); // second frame may not build again
      expect(m.bs[1].bc, equals(1));
      expect(m.bs[2].bc, equals(1));
      m.tap[1];
      await wt.pump();
      expect(m.bs[0].bc, equals(1)); // child should NOT rebuild after tap
      expect(m.bs[1].bc, equals(2)); // tapped should rebuild after tap
      expect(m.bs[2].bc, equals(1)); // parent should NOT rebuild after tap
    });
    // testWidgets('Visibility STATE' // uses offstage tested above
    testWidgets('Visibility NONE', (wt) async {
      await wt.pumpWidget(Visibility(visible: false, child: wtop));
      expect(m.bs[0].bc, equals(0)); // not visible does not run build at all
      expect(m.bs[1].bc, equals(0));
      expect(m.bs[2].bc, equals(0));
      await wt.pump();
      expect(m.bs[0].bc, equals(0));
      expect(m.bs[1].bc, equals(0));
      expect(m.bs[2].bc, equals(0));
      m.tap[1];
      await wt.pump();
      expect(m.bs[0].bc, equals(0));
      expect(m.bs[1].bc, equals(0));
      expect(m.bs[2].bc, equals(0));
    });
  });
  group('inners', () {
    late TestModel m;
    late BuildsWatcher wtop;
    setUp(() {
      m = TestModel();
      wtop = BuildsWatcher(m: m, pos: 0, smMask: 1);
    });
    testWidgets('forwarders', (wt) async {
      await wt.pumpWidget(wtop);
      expect(m.bs[0].bc, equals(1)); // initial build should be counted
      m[1] = m[0] ? true : true;
      int o = (m.tg.notifier as UiNotifier).observers;
      expect(o, equals(1));
      expect(m[0], isFalse);
      expect(m[1], isTrue);
      await wt.pump();
      expect(m.bs[0].bc, equals(1)); // [0] should not change
      // (m.tg.notifier as UiNotifier).dispose();
      // o = (m.tg.notifier as UiNotifier).observers;
    });
    /* IDNKy how to test for bad unregistrations exceptions
      testWidgets('bad unregister', (wt) async {
        await wt.pumpWidget(wtop);
        expect(m.bs[0].bc, equals(1)); // initial build should be counted
        int o = (m.tg.notifier as UiNotifier).observers;
        expect(o, equals(1));
        (m.tg.notifier as UiNotifier).dispose();
        o = (m.tg.notifier as UiNotifier).observers;
        expect(o, equals(0));
        wt.pump();
        expect(wt.binding.takeException(), isA<AssertionError>);
        wt.binding.takeException();
      });*/

    testWidgets('not watched', (wt) async {
      await wt.pumpWidget(wtop);
      expect(m.bs[0].bc, equals(1)); // initial build should be counted
      m[1] = m[0] ? true : true;
      expect(m[0], isFalse);
      expect(m[1], isTrue);
      await wt.pump();
      expect(m.bs[0].bc, equals(1)); // [0] should not change
      m.E[1] = true;
      await wt.pump();
      expect(m.bs[0].bc, equals(1)); // [0] should not change
    });
    testWidgets('conditional watch', (wt) async {
      await wt.pumpWidget(wtop);
      expect(m.bs[0].bc, equals(1)); // initial build should be counted
      m.tap[tgLastFlag];
      await wt.pump();
      expect(m.bs[0].bc, equals(1)); // should not watch tgLastFlag
      // m.E[0] = false; // disable
      m.tg.disable(0);
      await wt.pump();
      expect(m.bs[0].bc, equals(2)); // should rebuild after disable
      //await wt.pump();
      //expect(m.bs[0].bc, equals(2)); // no changes
      //m.tap[tgLastFlag];
      //expect(m.bs[0].bc, equals(3)); // should observe LastFlag now
    });
  });
  // group('newgroup', () { setUp(() {}); });
}
