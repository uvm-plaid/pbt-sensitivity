{-# LANGUAGE
    AllowAmbiguousTypes
   ,DataKinds
   ,FlexibleContexts
   ,GADTs
   ,GeneralizedNewtypeDeriving
   ,KindSignatures
   ,PartialTypeSignatures
   ,PolyKinds
   ,RankNTypes
   ,ScopedTypeVariables
   ,TypeApplications
   ,TypeFamilies
   ,TypeOperators
   ,TypeSynonymInstances
   ,TypeFamilyDependencies
   ,UndecidableInstances
   ,RebindableSyntax
   ,EmptyCase
   #-}
module Solo2 where
import Prelude hiding (return,(>>=), sum)
import qualified Prelude as P
import qualified GHC.TypeLits as TL
import Data.Proxy

import Sensitivity
import Privacy
import Primitives
import StdLib
import Rats


--------------------------------------------------
-- Simple examples
--------------------------------------------------

dbl :: SDouble Diff senv -> SDouble Diff (senv +++ senv)
dbl x = x <+> x

simplePrivacyFunction :: TL.KnownNat (MaxSens (s +++ s)) =>
  SDouble Diff s -> PM (TruncatePriv (RNat 2) Zero (s +++ s)) Double
simplePrivacyFunction x = laplace @(RNat 2) (dbl x)

addNoiseTwice :: TL.KnownNat (MaxSens s) => SDouble Diff s
  -> PM (TruncatePriv (RNat 2) Zero s ++++ TruncatePriv (RNat 3) Zero s) Double
addNoiseTwice x = do
  a <- laplace @(RNat 2) x
  b <- laplace @(RNat 3) x
  return $ a + b

-- FAIL version from the paper:
-- sumList xs = sfoldr (<+>) (sConstD '[] 0) xs

-- Correct version
sumList :: L1List (SDouble Diff) s -> SDouble Diff s
sumList xs = cong scale_unit $ sfoldr @1 @1 scalePlus (sConstD @'[] 0) xs
  where scalePlus a b = cong (eq_sym scale_unit) a <+> cong (eq_sym scale_unit) b

--------------------------------------------------
-- CDF Example
--------------------------------------------------

cdf :: forall ε iterations s. (TL.KnownNat (MaxSens s), TL.KnownNat iterations) =>
  [Double] -> L1List (SDouble Disc) s -> PM (ScalePriv (TruncatePriv ε Zero s) iterations) [Double]
cdf buckets db = seqloop @iterations (\i results -> do
                                         let c = count $ sfilter ((<) $ buckets !! i) db
                                         r <- laplace @ε c
                                         return (r : results)) []

exampleDB :: L1List (SDouble Disc) '[ '( "input_db", NatSens 1 ) ]
exampleDB = undefined

-- -- ε = 100
examplecdf :: PM '[ '( "input_db", RNat 100, Zero ) ] [Double]
examplecdf = cdf @(RNat 1) @100 [0..100] exampleDB

--------------------------------------------------
-- Gradient descent example
--------------------------------------------------

type Weights = [Double]
type Example = [Double]
type SExample = L2List (SDouble Disc)
type SDataset senv = L1List SExample senv
gradient :: Weights -> Example -> Weights
gradient = undefined


clippedGrad :: forall senv cm m.
  Weights -> SExample senv -> L2List (SDouble Diff) (TruncateSens 1 senv)
clippedGrad weights x =
  let g = infsensL (gradient weights) x         -- apply the infinitely-sensitive function
  in cong (truncate_n_inf @1 @senv) $ clipL2 g  -- clip the results and return

gradientDescent :: forall ε δ iterations s.
  (TL.KnownNat iterations) =>
  Weights -> SDataset s -> PM (ScalePriv (TruncatePriv ε δ s) iterations) Weights
gradientDescent weights xs =
  let gradStep i weights =
        let clippedGrads = stmap @1 (clippedGrad weights) xs
            gradSum = sfoldr1s sListSum1s (sConstL @'[] []) clippedGrads
        in gaussLN @ε @δ @1 @s gradSum
  in seqloop @iterations gradStep weights

gradientDescentAdv :: forall ε δ iterations s.
  (TL.KnownNat iterations) =>
  Weights -> SDataset s -> PM (AdvComp iterations δ (TruncatePriv ε δ s)) Weights
gradientDescentAdv weights xs =
  let gradStep i weights =
        let clippedGrads = stmap @1 (clippedGrad weights) xs
            gradSum = sfoldr1s sListSum1s (sConstL @'[] []) clippedGrads
        in gaussLN @ε @δ @1 @s gradSum
  in advloop @iterations @δ gradStep weights

-- SExample of passing in specific numbers to reduce the expression down to literals
-- Satisfies (1, 1e-5)-DP
gdMain :: PM '[ '("dataset.dat", RNat 1, RLit 1 100000) ] Weights
gdMain =
  let weights = take 10 $ repeat 0
      dataset = sReadFile @"dataset.dat"
  in gradientDescent @(RLit 1 100) @(RLit 1 10000000) @100 weights dataset

--------------------------------------------------
-- k-means clustering example
--------------------------------------------------

type SPoint s = L1Pair (SDouble Diff) (SDouble Diff) s
type SPoints s = L1List (L1Pair (SDouble Disc) (SDouble Disc)) s

-- dist :: forall s. Double -> SDouble Disc s -> SDouble Diff (TruncateSens 1 s)
-- dist p1 p2 = truncate_inf @1 @s $ clipDouble $ infsensD (\x -> abs $ p1 - x) p2

-- this involves a bunch of crazy stuff like partitioning
-- I think we should not bother

--------------------------------------------------
-- MWEM
--------------------------------------------------

type RangeQuery = (Double, Double)
evaluateDB :: RangeQuery -> L1List (SDouble Disc) s -> SDouble Diff s
evaluateDB (l, u) db = count $ sfilter (\x -> l < x && u > x) db
evaluateSynth :: RangeQuery -> [Double] -> Double
evaluateSynth (l, u) syn_rep = fromIntegral $ length $ filter (\x -> l < x && u > x) syn_rep

scoreFn :: forall s. [Double] -> RangeQuery -> L1List (SDouble Disc) s -> SDouble Diff s
scoreFn syn_rep q db =
  let true_answer = evaluateDB q db
      syn_answer  = evaluateSynth q syn_rep
  in sabs $ sConstD @'[] syn_answer <-> true_answer

mwem :: forall ε iterations s.
  (TL.KnownNat (MaxSens s), TL.KnownNat iterations) =>
  [Double] -> [RangeQuery] -> L1List (SDouble Disc) s
  -> PM (ScalePriv ((TruncatePriv ε Zero s) ++++ (TruncatePriv ε Zero s)) iterations) [Double]
mwem syn_rep qs db =
  let mwemStep _ syn_rep = do
        selected_q <- expMech @ε (scoreFn syn_rep) qs db
        measurement <- laplace @ε (evaluateDB selected_q db)
        return $ multiplicativeWeights syn_rep selected_q measurement
  in seqloop @iterations mwemStep syn_rep

multiplicativeWeights :: [Double] -> (Double, Double) -> Double -> [Double]
multiplicativeWeights = undefined
