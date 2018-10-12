{-# LANGUAGE DefaultSignatures, FunctionalDependencies, RankNTypes #-}
module Control.Effect.Handler
( HFunctor(..)
, Effect(..)
, Carrier(..)
, Effectful
, handlePure
) where

class HFunctor h where
  -- | Functor map. This is required to be 'fmap'.
  --
  --   This can go away once we have quantified constraints.
  fmap' :: (a -> b) -> (h m a -> h m b)
  default fmap' :: Functor (h m) => (a -> b) -> (h m a -> h m b)
  fmap' = fmap

  -- | Higher-order functor map of a natural transformation over higher-order positions within the effect.
  hfmap :: (forall x . m x -> n x) -> (h m a -> h n a)


-- | The class of effect types, which must:
--
--   1. Be functorial in their last two arguments, and
--   2. Support threading effects in higher-order positions through using the carrier’s suspended state.
class HFunctor sig => Effect sig where
  -- | Handle any effects in higher-order positions by threading the carrier’s state all the way through to the continuation.
  handle :: Functor f
         => f ()
         -> (forall x . f (m x) -> n (f x))
         -> sig m (m a)
         -> sig n (n (f a))


-- | The class of carriers (results) for algebras (effect handlers) over signatures (effects), whose actions are given by the 'gen' and 'alg' methods.
class HFunctor sig => Carrier sig h | h -> sig where
  gen :: a -> h a
  alg :: sig h (h a) -> h a

-- | The class of 'Monad'ic computations handling 'Effect's.
class (Monad m, Carrier sig m, Effect sig) => Effectful sig m | m -> sig


-- | Apply a handler specified as a natural transformation to both higher-order and continuation positions within an 'HFunctor'.
handlePure :: HFunctor sig => (forall x . f x -> g x) -> sig f (f a) -> sig g (g a)
handlePure handler = hfmap handler . fmap' handler
{-# INLINE handlePure #-}