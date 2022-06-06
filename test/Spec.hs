import Test.QuickCheck (quickCheck, withMaxSuccess)
import Verifier (prop_distance, prop_distance_solo)

test_distance :: IO ()
test_distance = quickCheck (withMaxSuccess 1000 prop_distance)

test_distance_solo :: IO ()
test_distance_solo = quickCheck (withMaxSuccess 1000 prop_distance_solo)

main :: IO ()
main = do
  putStrLn "Testing distance compare without solo"
  test_distance
  putStrLn "Testing distance compare with solo"
  test_distance_solo
