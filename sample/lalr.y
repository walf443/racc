# This is LALR grammar, and not LL/SLR.

class A
rule
  A : L '=' E

  L : i
    | R '^' i

  E : E '+' R
    | R
    | '@' L

  R : i
end
