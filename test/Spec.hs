{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -ddump-splices #-}

import AnnotatedExternalLibrary (add_dependently_typed_matrix_solo, add_matrix_solo, add_pair_solo, solo_mixed_types, solo_mixed_types_mult, solo_plus, solo_plus_incorrect)
import Control.Monad
import Control.Monad.Random
import Debug.Trace qualified as Debug
import Distance
import DpMinst (randomMnist, testZeros, SGradients (..), flattenGrads, testHMatrixFoldr)
import DpMinst qualified
import GHC.TypeLits (KnownNat)
import Sensitivity
import TH (genMainQuickCheck, genProp)
import Test.QuickCheck (quickCheck, withMaxSuccess)
import Utils

f = add_dependently_typed_matrix_solo @2 @4

{- $( genMainQuickCheck
    "tests"
    [ 'solo_plus
    , 'add_pair_solo
    , 'f
    , 'solo_mixed_types
    , 'solo_mixed_types_mult
    ]
 )
-}
$( do
    x <- genProp 'DpMinst.clippedGrad2
    pure [x]
 )

sensCheckDPClippedGrad = do
  net0 <- evalRandIO randomMnist
  --Debug.traceShowM net0
  -- TODO fix the ordering bug so I don't need to curry
  quickCheck $ withMaxSuccess 10000 (\sl1 sl2 -> clippedGrad2_prop sl1 sl2 $! net0)
  -- putStrLn $ show $ flattenGrads $ testZeros net0

-- $(genMainQuickCheck "failing_tests" ['add_matrix_solo, 'solo_plus_incorrect])

main :: IO ()
main = do
  putStrLn "\n\nThese tests are expected to pass:"
  sensCheckDPClippedGrad
  testHMatrixALot
  --  tests
  putStrLn "\n\n=================================="

-- putStrLn "These tests are expected to fail:\n\n"
-- failing_tests

testHMatrixALot = do
  testHMatrixFoldr
  testHMatrixFoldr
  testHMatrixFoldr
  testHMatrixFoldr
  testHMatrixFoldr
  testHMatrixFoldr
  testHMatrixFoldr
  testHMatrixFoldr