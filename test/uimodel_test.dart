import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:uimodel/uimodel.dart';

class SimpleModel with UiModel {
  int taps = 0;
  SimpleModel() {
    tg.notifier = UiNotifier();
  }
  void up() {
    taps++;
    tg.toggle(0);
  }
}

class SimpleWatcher extends UiModeledWidget {
  final SimpleModel m;
  final int tag;
  SimpleWatcher({super.key, required this.m, this.tag = 0});

  @override
  Widget build(BuildContext context) {
    return Container();
  }
}

class Stw extends StatefulWidget {
  Stw({super.key});
  final SimpleModel m = SimpleModel();

  @override
  State<Stw> createState() => StwState();
}

class StwState extends State<Stw> {
  int builds = 0;
  @override
  Widget build(BuildContext context) {
    builds++;
    final m = widget.m;
    //return m[0] ? SimpleWatcher(m: m, tag: 1) : SimpleWatcher(m: m, tag: 2);
    return m.taps & 1 == 0
        ? SimpleWatcher(m: m, tag: 1)
        : SimpleWatcher(m: m, tag: 2);
  }

  void tap0() => setState(() => widget.m.up());
}

/// our model to tests
class TestModel with UiModel {
  final sub1 = SubModel();
  final sub2 = SubModel(100);
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

/// inherited bool
class OneOrAnother extends InheritedWidget {
  final bool value;
  const OneOrAnother({super.key, required this.value, required super.child});
  static OneOrAnother of(BuildContext context) {
    final OneOrAnother? result =
        context.dependOnInheritedWidgetOfExactType<OneOrAnother>();
    return result!;
  }

  @override
  bool updateShouldNotify(OneOrAnother old) => value != old.value;
}

/// trying to get to update
class DoubleW extends UiModeledWidget {
  final TestModel m;
  final Widget w1;
  final Widget w2;
  DoubleW({super.key, required this.m, required this.w1, required this.w2});

  @override
  Widget build(BuildContext context) {
    return m[5] ? w1 : w2;
  }
}

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
    watches(m.sub1, 1); // watch also two submodels
    watches(m.sub2, 1);
    final bs = m.bs[pos];
    bs.bc++;
    bs.wasSet = m[pos];
    bs.wasEnabled = m.E[pos];
    return child ?? const SizedBox.shrink();
  }
}

class RegTwice extends UiModeledWidget {
  final TestModel m;
  RegTwice({super.key, required this.m});
  @override
  Widget build(BuildContext context) {
    watches(m, 33);
    watches(m, 65);
    return const SizedBox.shrink();
  }
}

const tgLastFlag = 5;
const smLastFlag = 1 << 5;

class SubModel with UiModel {
  int cnt;
  SubModel([this.cnt = 0]) {
    tg.notifier = UiNotifier();
  }
  void up() {
    cnt++;
    tg.toggle(0);
  }
}

void main() {
  group('simple ::', () {
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
                  child: BuildsWatcher(
                    m: m,
                    pos: 3,
                    smMask: 4, // two elements for same mask
                    child: RegTwice(m: m), // two masks for same element
                  ))));
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
  group('inners ::', () {
    late TestModel m;
    late BuildsWatcher wtop;
    setUp(() {
      m = TestModel();
      wtop = BuildsWatcher(m: m, pos: 0, smMask: 1);
    });
    test('model forwarders', () {
      // make sure coverage-ignored forwarders work
      // https://github.com/flutter/flutter/issues/31856
      dynamic spare;
      spare = m[11];
      expect(spare, isA<bool>());
      spare = m.E[11];
      expect(spare, isA<bool>());
      m[11] = true;
      expect(m[11], isTrue);
      expect(m.tg.bits & 1 << 11 != 0, isTrue);
      m[11] = false;
      expect(m[11], isFalse);
      expect(m.tg.bits & 1 << 11 != 0, isFalse);
      m.E[11] = false; // disable ds ->1
      expect(m.E[11], isFalse);
      expect(m.tg.ds & 1 << 11 != 0, isTrue);
      m.E[11] = true; // enable ds ->0
      expect(m.E[11], isTrue);
      expect(m.tg.ds & 1 << 11 != 0, isFalse);
      m.tg.bits = 0;
      m.toggle(11);
      expect(m[11], isTrue);
      expect(m.tg.bits, equals(1 << 11));
      m.toggle(11);
      expect(m[11], isFalse);
      expect(m.tg.bits, equals(0));
    });
    testWidgets('observers', (wt) async {
      await wt.pumpWidget(wtop);
      expect(m.bs[0].bc, equals(1)); // initial build should be counted
      int o = (m.tg.notifier as UiNotifier).observers;
      expect(o, equals(1));
      o = (m.sub1.tg.notifier as UiNotifier).observers;
      expect(o, equals(1));
      o = (m.sub2.tg.notifier as UiNotifier).observers;
      expect(o, equals(1));
    });

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
  group('tree tricks ::', () {
    late TestModel m;
    late Widget wtop;
    setUp(() {
      m = TestModel();
      wtop = DoubleW(
        m: m,
        w1: const SizedBox.shrink(key: Key('same')),
        w2: const SizedBox.expand(key: Key('same')),
      );
    });

    testWidgets('conditional watch', (wt) async {
      await wt.pumpWidget(wtop);
      await wt.pump();
      m[5] = true;
      await wt.pump();
      expect(m[5], isTrue);
    });
  });
  group('update ::', () {
    setUp(() {
      // m = SimpleModel();
    });
    testWidgets('Immerse', (wt) async {
      final xx = Stw(key: const Key('stw'));
      await wt.pumpWidget(xx);
      expect(xx.m.taps, equals(0));
      xx.m.up();
      await wt.pump();
      expect(xx.m.taps, equals(1));
      xx.m.up();
      await wt.pump();
      expect(xx.m.taps, equals(2));
    });
  });
  group('multi ::', () {
    late TestModel m;
    late Widget wtop;
    setUp(() {
      m = TestModel();
      wtop = BuildsWatcher(m: m, pos: 2, smMask: 4);
    });

    testWidgets('watch', (wt) async {
      await wt.pumpWidget(wtop);
      await wt.pump();
      m[5] = true;
      await wt.pump();
      expect(m[5], isTrue);
    });
    testWidgets('submodels watched', (wt) async {
      await wt.pumpWidget(wtop);
      expect(m.bs[2].bc, equals(1)); // initial build should be counted
      await wt.pump();
      expect(m.bs[2].bc, equals(1)); // nothing to rebuild
      expect(m.sub1.cnt, equals(0));
      expect(m.sub2.cnt, equals(100));
      m.sub1.up();
      await wt.pump();
      expect(m.bs[2].bc, equals(2)); // wtop watches sub1
      expect(m.sub1.cnt, equals(1));
      m.sub2.up();
      await wt.pump();
      expect(m.bs[2].bc, equals(3)); // wtop watches sub2
      expect(m.sub2.cnt, equals(101));
    });
  });
  // group('newgroup', () { setUp(() {}); });
}
