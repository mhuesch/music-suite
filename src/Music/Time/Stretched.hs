
{-# LANGUAGE DeriveDataTypeable         #-}
{-# LANGUAGE DeriveFoldable             #-}
{-# LANGUAGE DeriveFunctor              #-}
{-# LANGUAGE DeriveTraversable          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE RankNTypes                 #-}
{-# LANGUAGE TypeFamilies               #-}

-------------------------------------------------------------------------------------
-- |
-- Copyright   : (c) Hans Hoglund 2012-2014
--
-- License     : BSD-style
--
-- Maintainer  : hans@hanshoglund.se
-- Stability   : experimental
-- Portability : non-portable (TF,GNTD)
--
-------------------------------------------------------------------------------------

module Music.Time.Stretched (
        -- * Stretched type
        Stretched,
        -- * Construction
        stretched,
        stretchee,
        durationStretched,
        stretchedComplement,
  ) where

import           Control.Applicative
import           Control.Lens           hiding (Indexable, Level, above, below,
                                         index, inside, parts, reversed,
                                         transform, (<|), (|>))
import           Data.Bifunctor
import           Data.Foldable          (Foldable)
import qualified Data.Foldable          as Foldable
import           Data.Functor.Couple
import           Data.String
import           Data.Typeable
import           Data.VectorSpace

import           Music.Dynamics.Literal
import           Music.Pitch.Literal
import           Music.Time.Reverse
import           Music.Time.Split


-- |
-- A value 'Stretched' value, representing a suspended stretch of some 'Transformable'
-- value. We can access the value in bothits original and stretched form using 'stretched'
-- and 'stretchee', respectively.
--
-- Placing a value inside 'Stretched' makes it invariant under 'delay', however the inner
-- value can still be delayed using @'fmap' 'delay'@.
--
newtype Stretched a = Stretched { _stretchee :: Couple Duration a }
  deriving (
    Eq,           Num,      Fractional,   Floating,
    Ord,          Real,     RealFrac,     Functor,
    Applicative,  Monad,    Foldable,     Traversable, Typeable
    )
            -- Comonad,

instance Wrapped (Stretched a) where
  type Unwrapped (Stretched a) = (Duration, a)
  _Wrapped' = iso (getCouple . _stretchee) (Stretched . Couple)

instance Rewrapped (Stretched a) (Stretched b)

-- $semantics Stretched
--
-- @
-- type Stretched = (Duration, a)
-- @
--

-- >>> stretch 2 $ (5,1)^.stretched
-- (10,1)^.stretched
--
-- >>> delay 2 $ (5,1)^.stretched
-- (5,1)^.stretched
--
instance Transformable (Stretched a) where
  transform t = over _Wrapped $ first (transform t)

instance Reversible (Stretched a) where
  rev = stretch (-1)

instance Splittable a => Splittable (Stretched a) where
  beginning d = over _Wrapped $ \(s, v) -> (beginning d s, beginning d v)
  ending    d = over _Wrapped $ \(s, v) -> (ending    d s, ending    d v)

instance HasDuration (Stretched a) where
  _duration = _duration . view _Wrapped

instance IsString a => IsString (Stretched a) where
  fromString = pure . fromString

instance IsPitch a => IsPitch (Stretched a) where
  fromPitch = pure . fromPitch

instance IsInterval a => IsInterval (Stretched a) where
  fromInterval = pure . fromInterval

instance IsDynamics a => IsDynamics (Stretched a) where
  fromDynamics = pure . fromDynamics

instance (Show a, Transformable a) => Show (Stretched a) where
  show x = show (x^.from stretched) ++ "^.stretched"

-- | View a stretched value as a pair of the original value and a stretch factor.
stretched :: Iso (Duration, a) (Duration, b) (Stretched a) (Stretched b)
stretched = _Unwrapped

-- | Access the stretched value.
-- Taking a value out carries out the stretch (using the 'Transformable' instance),
-- while putting a value in carries out the reverse transformation.
--
-- >>> view stretchee $ (2,3::Duration)^.stretched
-- 6
--
-- >>> set stretchee 6 $ (2,1::Duration)^.stretched
-- (2,3)^.stretched
--
stretchee :: Transformable a => Lens (Stretched a) (Stretched a) a a
stretchee = _Wrapped `dep` (transformed . stretching)

-- | A stretched value as a duration carrying an associated value.
-- Whitness by picking a trivial value.
--
-- >>> 2^.durationStretched
-- (2,())^.stretched
--
durationStretched :: Iso' Duration (Stretched ())
durationStretched = iso (\d -> (d,())^.stretched) (^.duration)
-- >>> (pure ())^.from durationStretched
-- 1
-- >>> (pure () :: Stretched ())^.duration
-- 1

-- TODO could also be an iso...
stretchedComplement :: Stretched a -> Stretched a
stretchedComplement (Stretched (Couple (d,x))) = Stretched $ Couple (negateV d, x)
-- FIXME negateV is negate not recip
-- The negateV method should follow (^+^), which is (*) for durations (is this bad?)


-- TODO move
-- dep :: (a ~ b, d ~ c, s ~ t) => Lens s t (x,a) (x,b) -> (x -> Lens a b c d) -> Lens s t c d
dep :: Lens' s (x,a) -> (x -> Lens' a c) -> Lens' s c
dep l f = lens getter setter
  where
    getter s = let
      (x,a) = view l s
      l2    = f x
      in view l2 a
    setter s b = let
      (x,_) = view l s
      l2    = f x
      in set (l._2.l2) b s

