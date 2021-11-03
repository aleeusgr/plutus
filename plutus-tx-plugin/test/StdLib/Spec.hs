{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# OPTIONS_GHC -fplugin PlutusTx.Plugin -fplugin-opt PlutusTx.Plugin:defer-errors -fplugin-opt PlutusTx.Plugin:no-context #-}

module StdLib.Spec where

import Common
import Control.DeepSeq
import Control.Exception
import Control.Monad.IO.Class
import Data.Ratio ((%))
import GHC.Real (reduce)
import Hedgehog (MonadGen, Property)
import Hedgehog qualified
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Lib
import PlcTestUtils
import Test.Tasty (TestName)
import Test.Tasty.Hedgehog (testProperty)

import PlutusTx.Eq qualified as PlutusTx
import PlutusTx.Ord qualified as PlutusTx
import PlutusTx.Prelude qualified as PlutusTx
import PlutusTx.Ratio qualified as Ratio

import PlutusTx.Builtins.Internal (BuiltinData (..))
import PlutusTx.Code
import PlutusTx.Lift qualified as Lift
import PlutusTx.Plugin

import PlutusCore.Data qualified as PLC

import Data.Proxy

roundPlc :: CompiledCode (Ratio.Rational -> Integer)
roundPlc = plc (Proxy @"roundPlc") Ratio.round

tests :: TestNested
tests =
  testNested "StdLib"
    [ goldenUEval "ratioInterop" [ getPlc roundPlc, Lift.liftProgram (Ratio.fromGHC 3.75) ]
    , testRatioProperty "round" Ratio.round round
    , testRatioProperty "truncate" Ratio.truncate truncate
    , testRatioProperty "abs" (fmap Ratio.toGHC Ratio.abs) abs
    , pure $ testProperty "ord" testOrd
    , pure $ testProperty "divMod" testDivMod
    , pure $ testProperty "quotRem" testQuotRem
    , pure $ testProperty "reduce" testReduce
    , pure $ testProperty "Eq @Data" eqData
    , goldenPir "errorTrace" errorTrace
    ]

eitherToMaybe :: Either e a -> Maybe a
eitherToMaybe (Left _)  = Nothing
eitherToMaybe (Right x) = Just x

-- | Evaluate (deeply, to get through tuples) a value, throwing away any exception and just representing it as 'Nothing'.
tryHard :: (MonadIO m, NFData a) => a -> m (Maybe a)
tryHard a = eitherToMaybe <$> (liftIO $ try @SomeException $ evaluate $ force a)

testRatioProperty :: (Show a, Eq a) => TestName -> (Ratio.Rational -> a) -> (Rational -> a) -> TestNested
testRatioProperty nm plutusFunc ghcFunc = pure $ testProperty nm $ Hedgehog.property $ do
    rat <- Hedgehog.forAll $ Gen.realFrac_ (Range.linearFrac (-10000) 100000)
    let ghcResult = ghcFunc rat
        plutusResult = plutusFunc $ Ratio.fromGHC rat
    Hedgehog.annotateShow ghcResult
    Hedgehog.annotateShow plutusResult
    Hedgehog.assert (ghcResult == plutusResult)

testDivMod :: Property
testDivMod = Hedgehog.property $ do
    let gen = Gen.integral (Range.linear (-10000) 100000)
    (n1, n2) <- Hedgehog.forAll $ (,) <$> gen <*> gen
    ghcResult <- tryHard $ divMod n1 n2
    plutusResult <- tryHard $ Ratio.divMod n1 n2
    Hedgehog.annotateShow ghcResult
    Hedgehog.annotateShow plutusResult
    Hedgehog.assert (ghcResult == plutusResult)

testQuotRem :: Property
testQuotRem = Hedgehog.property $ do
    let gen = Gen.integral (Range.linear (-10000) 100000)
    (n1, n2) <- Hedgehog.forAll $ (,) <$> gen <*> gen
    ghcResult <- tryHard $ quotRem n1 n2
    plutusResult <- tryHard $ Ratio.quotRem n1 n2
    Hedgehog.annotateShow ghcResult
    Hedgehog.annotateShow plutusResult
    Hedgehog.assert (ghcResult == plutusResult)

testReduce :: Property
testReduce = Hedgehog.property $ do
    let gen = Gen.integral (Range.linear (-10000) 100000)
    (n1, n2) <- Hedgehog.forAll $ (,) <$> gen <*> gen
    ghcResult <- tryHard $ reduce n1 n2
    plutusResult <- tryHard $ Ratio.toGHC $ Ratio.reduce n1 n2
    Hedgehog.annotateShow ghcResult
    Hedgehog.annotateShow plutusResult
    Hedgehog.assert (ghcResult == plutusResult)

testOrd :: Property
testOrd = Hedgehog.property $ do
    let gen = Gen.integral (Range.linear (-10000) 100000)
    n1 <- Hedgehog.forAll $ (%) <$> gen <*> gen
    n2 <- Hedgehog.forAll $ (%) <$> gen <*> gen
    ghcResult <- tryHard $ n1 <= n2
    plutusResult <- tryHard $ (PlutusTx.<=) (Ratio.fromGHC n1) (Ratio.fromGHC n2)
    Hedgehog.annotateShow ghcResult
    Hedgehog.annotateShow plutusResult
    Hedgehog.assert (ghcResult == plutusResult)

eqData :: Property
eqData = Hedgehog.property $ do
    theData <- BuiltinData <$> Hedgehog.forAll genData
    let ghcResult = theData == theData
        plutusResult = theData PlutusTx.== theData
    Hedgehog.annotateShow theData
    Hedgehog.assert (ghcResult && plutusResult)

genData :: MonadGen m => m PLC.Data
genData =
    let genInteger = Gen.integral (Range.linear (-10000) 100000)
        genBytes   = Gen.bytes (Range.linear 0 1000)
        genList    = Gen.list (Range.linear 0 10)
    in Gen.recursive
            Gen.choice
            [ PLC.I <$> genInteger
            , PLC.B <$> genBytes
            ]
            [ PLC.Constr <$> genInteger <*> genList genData
            , PLC.Map <$> genList ((,) <$> genData <*> genData)
            , PLC.List <$> genList genData
            ]

errorTrace :: CompiledCode (Integer)
errorTrace = plc (Proxy @"errorTrace") (PlutusTx.traceError "")
