---
sidebar_position: 20
---

# GHC Extensions, Flags and Pragmas

Plutus Tx is a subset of Haskell and is compiled to Untyped Plutus Core by the Plutus Tx compiler, a GHC (Glasgow Haskell Compiler) plugin.

In order to ensure the success and correct compilation of Plutus Tx programs, all Plutus Tx modules (that is, Haskell modules that contain code to be compiled by the Plutus Tx compiler) should use the following GHC extensions, flags and pragmas.

### Extensions

Plutus Tx modules should use the `Strict` extension: :
```
    {-# LANGUAGE Strict #-}
```

As mentioned in [Differences from Haskell](./differences-from-haskell.md), function applications in Plutus Tx are always strict, while bindings can be strict or non-strict.
In addition, the UPLC evaluator does not perform lazy evaluation, meaning a non-strict binding is evaluated as many times as it is used.
Given these facts, making let bindings strict by default has the following advantages:

- It makes let bindings and function applications semantically equivalent. For example, `let x = 3 + 4 in 42` has the same semantics as `(\x -> 42) (3 + 4)`.
This is what one would come to expect, as it is the case in most other programming languages, regardless of whether the language is strict or non-strict.
- Using non-strict bindings can cause an expression to be inadvertently evaluated for an unbounded number of times.
Consider `let x = <expensive> in \y -> x + y`.
If `x` is non-strict, `<expensive>` will be evaluated every time `\y -> x + y` is applied to an argument, which means it can be evaluated 0 times, 1 time, 2 times, or any number of times (this is not the case if lazy evaluation was employed).
On the other hand, if `x` is strict, it is always evaluated once, which is at most one more time than what is necessary.

### Flags

GHC has a variety of optimization flags, many of which are on by default.
Although Plutus Tx is, syntactically, a subset of Haskell, it has different semantics and a different evaluation strategy (Haskell: non-strict semantics, call by need; Plutus Tx: strict semantics, call by value). As a result, some GHC optimizations are not helpful for Plutus Tx programs, and can even be harmful, in the sense that it can make Plutus Tx programs less efficient, or fail to be compiled.
An example is the full laziness optimization, controlled by GHC flag `-ffull-laziness`, which floats let bindings out of lambdas whenever possible.
Since Untyped Plutus Core does not employ lazy evaluation, the full laziness optimization is usually not beneficial, and can sometimes make a Plutus Tx program more expensive.
Conversely, some GHC features must be turned on in order to ensure Plutus Tx programs are compiled successfully.

All Plutus Tx modules should use the following GHC flags:
```
    -fno-ignore-interface-pragmas
    -fno-omit-interface-pragmas
    -fno-full-laziness
    -fno-spec-constr
    -fno-specialise
    -fno-strictness
    -fno-unbox-strict-fields
    -fno-unbox-small-strict-fields
```

`-fno-ignore-interface-pragmas` and `-fno-omit-interface-pragmas` ensure unfoldings of Plutus Tx functions are available.
The rest are GHC optimizations that are generally bad for Plutus Tx, and should thus be turned off.

These flags can be specified either in a Haskell module, for example:
```
    {-# OPTIONS_GHC -fno-ignore-interface-pragmas #-}
```
or in a build file.
For example, if your project is built using Cabal, you can add the flags to the `.cabal` files, like so:

```
ghc-options:
  -fno-ignore-interface-pragmas
```

> :pushpin: **NOTE**
>
> This section only covers GHC flags, not Plutus Tx compiler flags.
> A number of options can be passed to the Plutus Tx compiler.
> See [Plutus Tx Compiler Options](../delve-deeper/plutus-tx-compiler-options.md) for details.

### Pragmas

All functions and methods should have the `INLINEABLE` pragma (not the `INLINE` pragma, which should generally be avoided), so that their unfoldings are made available to the Plutus Tx compiler.

The `-fexpose-all-unfoldings` flag also makes GHC expose all unfoldings, but unfoldings exposed this way can be more optimized than unfoldings exposed via `INLINEABLE`.
In general, we do not want GHC to perform optimizations, since GHC optimizes a program based on the assumption that it has non-strict semantics and is evaluated lazily (call by need), which is not true for Plutus Tx programs.
Therefore, `INLINEABLE` is preferred over `-fexpose-all-unfoldings`, even though the latter is simpler.

`-fexpose-all-unfoldings` can be useful for functions that are generated by GHC and do not have the `INLINEABLE` pragma.
`-fspecialise` and `-fspec-constr` are two examples of optimizations that can generate such functions.
The most reliable solution, however, is to simply turn these optimizations off.
Another option is to bump `-funfolding-creation-threshold` to make it more likely for GHC to retain unfoldings for functions without the `INLINEABLE` pragma.
`-fexpose-all-unfoldings` should be used as a last resort.