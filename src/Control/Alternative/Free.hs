{-# LANGUAGE CPP #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE ScopedTypeVariables #-}
#if __GLASGOW_HASKELL__ >= 707
{-# LANGUAGE DeriveDataTypeable #-}
#endif
{-# OPTIONS_GHC -Wall #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  Control.Alternative.Free
-- Copyright   :  (C) 2012 Edward Kmett
-- License     :  BSD-style (see the file LICENSE)
--
-- Maintainer  :  Edward Kmett <ekmett@gmail.com>
-- Stability   :  provisional
-- Portability :  GADTs, Rank2Types
--
-- Left distributive 'Alternative' functors for free, based on a design
-- by Stijn van Drongelen.
----------------------------------------------------------------------------
module Control.Alternative.Free
  ( Alt(..)
    , AltF(..)
    , runAlt
    , liftAlt
    , hoistAlt
  ) where

import Control.Applicative
import Data.Functor.Apply
import Data.Semigroup

#ifdef GHC_TYPEABLE
import Data.Typeable
#endif

data AltF f a where
  Ap     :: f (a -> b) -> Alt f a -> AltF f b
  Pure   :: a                     -> AltF f  a
#if __GLASGOW_HASKELL__ >= 707
  deriving Typeable
#endif

newtype Alt f a = Alt { alternatives :: [AltF f a] }
#if __GLASGOW_HASKELL__ >= 707
  deriving Typeable
#endif

instance Functor f => Functor (AltF f) where
  fmap f (Pure a) = Pure (f a)
  fmap f (Ap g x) = Ap (fmap (f .) g) x

instance Functor f => Functor (Alt f) where
  fmap f (Alt xs) = Alt $ map (fmap f) xs
  
infixl 3 `Ap`

instance Functor f => Applicative (AltF f) where
  pure = Pure
  (Pure f)   <*> y                = fmap f y      -- fmap
  y          <*> (Pure a)         = fmap ($ a) y  -- interchange
  (Ap f a)   <*> (Ap g b)         = -- (f <*> a) <*> (g <*> b) == (fmap mangle f) <*> ((,) <$> a <*> ((,) <*> w <*> t))
                                    (fmap mangle f `Ap` ((fmap (,) a) <*> (Alt [Ap (fmap (,) g) b])))
                                      where
                                      mangle :: (a -> b -> c) -> (a, (d -> b, d)) -> c
                                      mangle f' (a',(g',d)) = f' a' (g' d)
 
instance Functor f => Applicative (Alt f) where
  pure a = Alt [pure a]

  -- distributivity of alternative
  (Alt xs) <*> ys = Alt (xs >>= alternatives . (`ap'` ys))
    where

      -- Pure f <*> u == fmap f u
      ap' :: (Functor f) => AltF f (a -> b) -> Alt f a -> Alt f b
      Pure f `ap'` u@(Alt _)  = fmap f u

      -- (u <*> v <*> w) == uncurry <$> u <*> ((,) <$> v <*> w)
      (Ap u v) `ap'` w  = Alt [(uncurry `fmap` u) `Ap` (((,) <$> v) <*> w)]
  

liftAltF :: (Functor f) => f a -> AltF f a
liftAltF x = Ap (fmap const x) (Alt [Pure ()])

-- | A version of 'lift' that can be used with just a 'Functor' for @f@.
liftAlt :: (Functor f) => f a -> Alt f a
liftAlt = Alt . (:[]) . liftAltF
    
-- | Given a natural transformation from @f@ to @g@, this gives a canonical monoidal natural transformation from @'Alt' f@ to @g@.
runAlt :: forall f g a. Alternative g => (forall x. f x -> g x) -> Alt f a -> g a
runAlt u xs0 = go xs0 where
  
  go  :: Alt f b -> g b
  go (Alt xs) = foldr (\r a -> (go2 r) <|> a) empty xs

  go2 :: AltF f b -> g b
  go2 (Pure a) = pure a
  go2 (Ap f x) = u f <*> go x


instance (Functor f) => Apply (Alt f) where
  (<.>) = (<*>)
                     
instance (Functor f) => Alternative (Alt f) where
  empty = Alt []
  {-# INLINE empty #-}
  Alt as <|> Alt bs = Alt (as ++ bs)
  {-# INLINE (<|>) #-}

instance (Functor f) => Semigroup (Alt f a) where
  (<>) = (<|>)
  {-# INLINE (<>) #-}

instance (Functor f) => Monoid (Alt f a) where
  mempty = empty
  {-# INLINE mempty #-}
  mappend = (<|>)
  {-# INLINE mappend #-}
  mconcat as = Alt (as >>= alternatives)
  {-# INLINE mconcat #-}

{-# INLINE liftAlt #-}

hoistAltF :: (forall a. f a -> g a) -> AltF f b -> AltF g b
hoistAltF _ (Pure a) = Pure a
hoistAltF f (Ap x y) = Ap (f x) (hoistAlt f y)

-- | Given a natural transformation from @f@ to @g@ this gives a monoidal natural transformation from @Alt f@ to @Alt g@.
hoistAlt :: (forall a. f a -> g a) -> Alt f b -> Alt g b
hoistAlt f (Alt as) = Alt (map (hoistAltF f) as)

#if defined(GHC_TYPEABLE) && __GLASGOW_HASKELL__ < 707
instance Typeable1 f => Typeable1 (Alt f) where
  typeOf1 t = mkTyConApp altTyCon [typeOf1 (f t)] where
    f :: Alt f a -> f a
    f = undefined

altTyCon :: TyCon
#if __GLASGOW_HASKELL__ < 704
altTyCon = mkTyCon "Control.Alternative.Free.Alt"
#else
altTyCon = mkTyCon3 "free" "Control.Alternative.Free" "Alt"
#endif
{-# NOINLINE altTyCon #-}

#endif

