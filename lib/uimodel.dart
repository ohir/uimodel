// Copyright (c) 2022 Wojciech S. Czarnecki, aka Ohir Ripe

/// Package [UiModel] is a thin wrapper around the [Toggler] package/class
/// bringing to it _Flutter_ bindings.  Working _Flutter_ app with state
/// management based on [Toggler] and [UiModel] can be found in the package's
/// 'example' folder.
///
/// With [UiModel] and [UiModelLink] all your widgets are "Stateless" in name,
/// yet they may observe Model(s) implemented with [UiModel] mixin and rebuild on
/// just particular changes within that Model, (or any of submodels it contains).
/// If you use "ambient" singleton Model all you need to observe it and rebuild
/// your Widget on a particular changes is a single `watches()` line, typically
/// given right under the `Widget build(...)`:
/// ```Dart
/// class Counter extends StatelessWidget with UiModelLink {
///   //  Counter extends UiModeledWidget { // shorter version of above
///   Counter({ Key? key, }) : super(key: key);
///   @override
///   Widget build(BuildContext context) {
///     watches(m, smDn | smUp | smInfo); // three flags in model 'm' observed
///     // watches(m.submodel, smSubSmth | smSubOther); // here: two of submodel
/// ```
library uimodel;

import 'package:flutter/widgets.dart';
import 'package:toggler/toggler.dart';

/// Adds a [Toggler] and [UiNotifier] to your ViewModel class and exposes a
/// small subset of Toggler api suitable for use from the View, ie. from
/// _Flutter_ Widget build methods.  If you need more, you can always reach for
/// the public `tg` Toggler. Eg. `text: 'ssn: ${pagemodel.tg.serial}',`.
///
/// _Note: Inside your ViewModel itself you should not use these wrapper
/// methods. You have the full [Toggler] api at your disposal there, with the
/// mixed-in `tg`._
mixin UiModel {
  /// internal [Toggler] with an [UiNotifier].
  ///
  /// Until your Flutter App main loop ran `tg` has no notifiers, so you can
  /// set-up your initial/restored state in ViewModel constructor at will.
  /// You should give it an UiNotifier after. (Or eg. a CiteNotifier for CI tests).
  late final tg = Toggler();

  // ignore till https://github.com/flutter/flutter/issues/31856 resolves
  // this is for sure covered by 'inners :: model forwarders' test
  // coverage:ignore-start
  /// returns state of _bool_ flag (item, bit) at _tgIndex_. 1:true 0:false
  bool operator [](int tgIndex) => tg[tgIndex];

  /// sets _bool_ flag (item, bit) at _tgIndex_ to given state. true:1 false:0
  void operator []=(int tgIndex, bool v) => tg[tgIndex] = v;

  /// toggle flag at _tgIndex_ to the opposite state
  void toggle(int tgIndex) => tg.toggle(tgIndex);

  /// Shorthand accessor of item's (flag, bit) disabled/active property.
  /// UI code usage: get: `m.E[tgIndex] ? : ;`, set: `m.E[tgIndex]=true|false`
  ///
  /// Not fastest in the pack, but allows for consistent use of `[tgIndex]` in
  /// the UI code.  If you must have it faster, use _tg_ directly, eg.
  /// `m.tg.active(tgIndex)`, `m.tg.enable(tgIndex)`, `m.tg.disable(tgIndex)`.
  TgIndexed<bool> get E => tg.E;
  // coverage:ignore-end
}

/// helper class to make item (flag, bit) related resources be avaliable
/// with index operator at `[tgName]`. You are free to use it within your models,
/// eg. to provide [Semantics] string to a flag.
class TgIndexed<T> {
  TgIndexed(this.gv, this.sv);
  final T Function(int i) gv;
  final void Function(int i, T v) sv;
  T operator [](int i) => gv(i);
  void operator []=(int i, T v) => sv(i, v);
}

/// add E getter to Toggler (just to expose it in [UiModel] for View code use)
extension TogglerEindexed on Toggler {
  TgIndexed<bool> get E => TgIndexed((i) => active(i), (i, v) => setDS(i, !v));
}

/// UiNotifier for Flutter Elements
///
/// _Note: [UiNotifier] binds deep into the render tree, hence it should not be
/// abandoned or replaced without disposing it first._
class UiNotifier extends ToggledNotifier {
  final _wama = <int, List<Element>>{}; // watched mask -> observers list

  // void dispose() => _wama.clear(); // usable only when all app is crashing anyway

  /// notify observers about changes
  @override
  void pump(int chb) {
    for (int k in _wama.keys) {
      if (k & chb == 0) continue;
      _wama[k]?.forEach((e) => e.markNeedsBuild());
    }
  }

  /// how many Widgets watches this notifier (diagnostics)
  ///
  /// Getter iterates over all active masks being watched by one or more observers.
  int get observers {
    int cnt = 0;
    for (final el in _wama.values) {
      cnt += el.length;
    }
    return cnt;
  }

  // this notifier bindings can be operated only from within an UiModelLink
  void _addElement(Element whom, int smMask) {
    final el = _wama[smMask];
    if (el == null) {
      _wama[smMask] = <Element>[whom];
      return;
    }
    // guarded in UiModelLink now
    // assert(!el.contains(whom), 'Bad! Element to notify tried to register again for the same mask!');
    el.add(whom);
  }

  void _removeElement(Element whom, int smMask) {
    final el = _wama[smMask];
// coverage:ignore-start
// XXX tests need a navigator, likely. We either must forego dispose on notifier,
// or must keep this assertion, for one who uses dispose after catching exception
//
    assert(el != null,
        'remove Element of not registered mask:$smMask for element:$whom');
// coverage:ignore-end
    if (el == null) return;
    el.remove(whom);
    if (el.isEmpty) _wama.remove(smMask);
  }
}

class _ElementWatching {
  int? _mask;
  UiNotifier? _uin;
  _ElementWatching(this._uin, this._mask);
}

class _MixinState {
  int? _smmask;
  UiNotifier? _uin;
  Element? _element;
  List<_ElementWatching>? _more;

  void init(Element element) => _element = element;

/* From the UI design it would be nice to have ability to bind widget to many
   (sub)models. Or change bindings on a next rebuild. This would be positive
   for stronger decoupling View and Model (ie. designer being free to make a
   screen piece from all data reachable via umbrella model, model developer
   free to not think on presentation layer). But this might complicate code
   and leak.
   Other solution is to restrict user to a strict rule "single element,
   single watches in build". We will do both experiments (as branches and see).
*/
  void bindNotifier(UiNotifier uin, int smMask) {
    if (_more == null) {
      if (smMask == _smmask && _uin == uin) return; // rewatching
      if (_smmask == null) {
        _uin = uin;
        _smmask = smMask;
        _uin!._addElement(_element!, smMask);
      } else if (uin != _uin) {
        _more = <_ElementWatching>[_ElementWatching(_uin, _smmask)];
        uin._addElement(_element!, smMask);
        _more!.add(_ElementWatching(uin, smMask));
        _uin = null;
        _smmask = null;
      } else {
        _uin!._removeElement(_element!, _smmask!); // watchmask changed
        _uin!._addElement(_element!, smMask);
        _smmask = smMask;
      }
      return;
    }
    for (int n = _more!.length - 1; n >= 0; n--) {
      final x = _more![n];
      if (x._uin == uin && x._mask == smMask) return; // rewatching
      if (x._uin == uin) {
        x._uin!._removeElement(_element!, x._mask!); // watchmask changed
        x._uin!._addElement(_element!, smMask);
        _more![n]._mask = smMask;
        return;
      }
    }
    uin._addElement(_element!, smMask);
    _more!.add(_ElementWatching(uin, smMask));
  }

  void dispose() {
    if (_more == null) {
      _uin?._removeElement(_element!, _smmask!);
      _uin = null;
    } else {
      for (int n = _more!.length - 1; n >= 0; n--) {
        final x = _more![n];
        x._uin!._removeElement(_element!, x._mask!);
        _more![n]._uin = null;
      }
      // _more!.clear();
      _more = null;
    }
    _element = null;
  }
}

/// Mixin that binds "stateless" Widget to your `ViewModel with UiModel`
/// using a single `watches(m, smThis | smThat | smYetAnother);` line.
///
/// _Proper spells allowing me to hook into StatelessWidget (and some code, of
/// course) lifted from [get_it_mixin](https://pub.dev/packages/get_it_mixin)
/// by @escamoteur. Thanks!_
mixin UiModelLink on StatelessWidget {
  final _MutableWrapper<_MixinState> _state = _MutableWrapper<_MixinState>();
  @override
  StatelessElement createElement() => _StatelessUiElement(this);

  /// observe flag changes in [UiModel] based _Model_. Or in any [UiModel] based
  /// submodels of your umbrella _Model_. A Widget with [UiModelLink] may
  /// observe more than one (sub)Model, one per each `watches` call; and it may
  /// change watched masks in subsequent builds.
  /// This is the only method added by [UiModelLink] mixin. It should be called
  /// at the top of your StatelessWidget `build` method.
  ///
  /// Watching a single Model is cheap both cpu and memory-wise, watching
  /// two or more internally makes a list of modelLinks then on each `build`
  /// link-check mechanics must iterate over list to find whether `watches`
  /// configuration had changed.
  ///
  /// While widget may not _"deregister"_ from the once being watched Model,
  /// it can set watched mask to 0 (smNone) to not be bothered anymore. If it
  /// does not watch anymore, it will never rebuild again, unless enforced
  /// externally eg. from an InheritedWidget changes (or route going out of
  /// scope).
  ///
  void watches<M extends UiModel>(M m, int smMask) =>
      _state.value.bindNotifier(m.tg.notifier as UiNotifier, smMask);
}

class _MutableWrapper<T> {
  late T value;
}

mixin _UiModelElement on ComponentElement {
  late _MixinState _state;

  @override
  void mount(Element? parent, dynamic newSlot) {
    _state.init(this);
    super.mount(parent, newSlot);
  }

  @override
  void unmount() {
    _state.dispose();
    super.unmount();
  }
  // Should we supress notify for elements with global keys? IdNKY
  // ie. deregister on deactivate then register again on activate?
  // @override void deactivate() { super.deactivate(); } // supress
  // @override void activate() { super.activate(); } // restore
}

class _StatelessUiElement<W extends UiModelLink> extends StatelessElement
    with _UiModelElement {
  _StatelessUiElement(
    W widget,
  ) : super(widget) {
    _state = _MixinState();
    widget._state.value = _state;
  }
  @override
  W get widget => super.widget as W;

  @override
  void update(W newWidget) {
    newWidget._state.value = _state;
    super.update(newWidget);
  }
}

/// A sugar shim for `StatelessWidget with UiModelLink`.  It makes clear to the
/// code reader that widget in UI observes changes in Model.
abstract class UiModeledWidget extends StatelessWidget with UiModelLink {
  UiModeledWidget({
    Key? key,
  }) : super(key: key);
}
