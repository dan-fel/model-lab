# A switch that flips; the Broken design lets a jam leave it in a third state.
import Base

type Policy is Data:
  Safe{}
  Broken{}

type Act is Data:
  Flip{}
  Jam{}

type Obligation is Data:
  OnIsBinary{}

type State is Data:
  State{on: Nat, flips: Nat}

def initial() -> State:
  State{0n, 0n}

def flip(s: State) -> State:
  match s:
    case State{+o, f}:
      State{Nat.sub(1n, Nat.min(o, 1n)), Nat.min((f + 1n), 2n)}

def jam(p: Policy, s: State) -> State:
  match p:
    case Broken{}:
      match s:
        case State{o, f}: State{2n, f}
    case p: s

def step(p: Policy, e: Act, s: State) -> State:
  match e:
    case Flip{}: flip(s)
    case Jam{}: jam(p, s)

def events() -> List<&2, Act>:
  [Flip{}, Jam{}]

def equal(left: State, right: State) -> Bool:
  match left right:
    case State{a, b} State{aa, bb}: Bool.and(Nat.is_eq(a, aa), Nat.is_eq(b, bb))

def rule(s: State, obligation: Obligation) -> Bool:
  match s:
    case State{on, f}:
      match obligation:
        case OnIsBinary{}: Nat.is_le(on, 1n)

def holds_in(obligation: Obligation, state: State) -> Bool:
  rule(state, obligation)

def holds(obligation: Obligation, before: State, after: State) -> Bool:
  rule(after, obligation)

def contains(states: List<&2, State>, +wanted: State) -> Bool:
  match states:
    case Nil{}: False{}
    case Con{head, tail}: Bool.or(equal(head, wanted), contains(tail, wanted))

def closed_events(remaining: List<&2, Act>, +p: Policy, +state: State, +states: List<&2, State>) -> Bool:
  match remaining:
    case Nil{}: True{}
    case Con{event, rest}:
      Bool.and(contains(states, step(p, event, state)), closed_events(rest, p, state, states))

def closed_states(todo: List<&2, State>, +p: Policy, +states: List<&2, State>) -> Bool:
  match todo:
    case Nil{}: True{}
    case Con{state, rest}:
      Bool.and(closed_events(events(), p, state, states), closed_states(rest, p, states))

def complete(p: Policy, +states: List<&2, State>) -> Bool:
  Bool.and(contains(states, initial()), closed_states(states, p, states))

def check(+obligation: Obligation, states: List<&2, State>) -> Bool:
  match states:
    case Nil{}: True{}
    case Con{state, rest}:
      Bool.and(rule(state, obligation), check(obligation, rest))
