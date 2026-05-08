abstract class GameState {
  void onEnter() {}
  void onExit() {}
  void update(double dt) {}
}

class StateMachine {
  StateMachine(this._current) {
    _current.onEnter();
  }

  GameState _current;
  GameState get current => _current;

  void transition(GameState next) {
    if (identical(next, _current)) return;
    _current.onExit();
    _current = next;
    next.onEnter();
  }

  void update(double dt) => _current.update(dt);
}
