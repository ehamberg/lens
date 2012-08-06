{-# LANGUAGE CPP #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE LiberalTypeSynonyms #-}
{-# LANGUAGE FlexibleContexts #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  Control.Lens.Setter
-- Copyright   :  (C) 2012 Edward Kmett
-- License     :  BSD-style (see the file LICENSE)
-- Maintainer  :  Edward Kmett <ekmett@gmail.com>
-- Stability   :  provisional
-- Portability :  Rank2Types
--
----------------------------------------------------------------------------
module Control.Lens.Setter
  (
  -- * Setters
    Setter
  -- * Consuming Setters
  , Setting
  -- * Building Setters
  , sets
  -- * Common Setters
  , mapped
  -- * Functional Combinators
  , adjust
  , mapOf
  , set
  , (.~), (%~)
  , (+~), (-~), (*~), (//~), (||~), (&&~), (<>~)
  -- * State Combinators
  , (.=), (%=)
  , (+=), (-=), (*=), (//=), (||=), (&&=), (<>=)
  -- * MonadWriter
  , whisper
  -- * Simplicity
  , SimpleSetter
  , SimpleSetting
  ) where

import Control.Applicative
import Control.Lens.Internal
import Control.Monad.State.Class        as State
import Control.Monad.Writer.Class       as Writer
import Data.Monoid

infixr 4 .~, +~, *~, -~, //~, &&~, ||~, %~, <>~
infix  4 .=, +=, *=, -=, //=, &&=, ||=, %=, <>=

------------------------------------------------------------------------------
-- Setters
------------------------------------------------------------------------------

-- |
-- The only 'Lens'-like law that can apply to a 'Setter' @l@ is that
--
-- > set l c (set l b a) = set l c a
--
-- You can't 'view' a 'Setter' in general, so the other two laws are irrelevant.
--
-- However, two functor laws apply to a 'Setter'
--
-- > adjust l id = id
-- > adjust l f . adjust l g = adjust l (f . g)
--
-- These an be stated more directly:
--
-- > l pure = pure
-- > l f . run . l g = l (f . run . g)
--
-- You can compose a 'Setter' with a 'Lens' or a 'Traversal' using @(.)@ from the Prelude
-- and the result is always only a 'Setter' and nothing more.
type Setter a b c d = forall f. Settable f => (c -> f d) -> a -> f b

-- |
-- Running a Setter instantiates it to a concrete type.
--
-- When consuming a setter, use this type.
type Setting a b c d = (c -> Mutator d) -> a -> Mutator b

-- |
-- > 'SimpleSetter' = 'Simple' 'Setter'
type SimpleSetter a b = Setter a a b b

-- |
-- > 'SimpleSetting' m = 'Simple' 'Setting'
type SimpleSetting a b = Setting a a b b

-- | This setter can be used to map over all of the values in a 'Functor'.
--
-- > fmap        = adjust mapped
-- > fmapDefault = adjust traverse
-- > (<$)        = set mapped
mapped :: Functor f => Setter (f a) (f b) a b
mapped = sets fmap
{-# INLINE mapped #-}

-- | Build a Setter from a map-like function.
--
-- Your supplied function @f@ is required to satisfy:
--
-- > f id = id
-- > f g . f h = f (g . h)
--
-- Equational reasoning:
--
-- > sets . adjust = id
-- > adjust . sets = id
--
-- Another way to view 'sets' is that it takes a 'semantic editor combinator'
-- and transforms it into a 'Setter'.
sets :: ((c -> d) -> a -> b) -> Setter a b c d
sets f g = pure . f (run . g)
{-# INLINE sets #-}

-- | Modify the target of a 'Lens' or all the targets of a 'Setter' or 'Traversal'
-- with a function.
--
-- > fmap        = adjust mapped
-- > fmapDefault = adjust traverse
--
-- > sets . adjust = id
-- > adjust . sets = id
--
-- > adjust :: Setter a b c d -> (c -> d) -> a -> b
--
-- Another way to view 'adjust' is to say that it transformers a 'Setter' into a
-- \"semantic editor combinator\".
adjust :: Setting a b c d -> (c -> d) -> a -> b
adjust l f = runMutator . l (Mutator . f)
{-# INLINE adjust #-}

-- | Modify the target of a 'Lens' or all the targets of a 'Setter' or 'Traversal'
-- with a function. This is an alias for adjust that is provided for consistency.
--
-- > mapOf = adjust
--
-- > fmap        = mapOf mapped
-- > fmapDefault = mapOf traverse
--
-- > sets . mapOf = id
-- > mapOf . sets = id
--
-- > mapOf :: Setter a b c d      -> (c -> d) -> a -> b
-- > mapOf :: Iso a b c d         -> (c -> d) -> a -> b
-- > mapOf :: Lens a b c d        -> (c -> d) -> a -> b
-- > mapOf :: Traversal a b c d   -> (c -> d) -> a -> b
mapOf :: Setting a b c d -> (c -> d) -> a -> b
mapOf = adjust
{-# INLINE mapOf #-}

-- | Replace the target of a 'Lens' or all of the targets of a 'Setter'
-- or 'Traversal' with a constant value.
--
-- > (<$) = set mapped
--
-- > set :: Setter a b c d    -> d -> a -> b
-- > set :: Iso a b c d       -> d -> a -> b
-- > set :: Lens a b c d      -> d -> a -> b
-- > set :: Traversal a b c d -> d -> a -> b
set :: Setting a b c d -> d -> a -> b
set l d = runMutator . l (\_ -> Mutator d)
{-# INLINE set #-}

-- | Modifies the target of a 'Lens' or all of the targets of a 'Setter' or
-- 'Traversal' with a user supplied function.
--
-- This is an infix version of 'adjust'
--
-- > fmap f = mapped %~ f
-- > fmapDefault f = traverse %~ f
--
-- > ghci> _2 %~ length $ (1,"hello")
-- > (1,5)
--
-- > (%~) :: Setter a b c d    -> (c -> d) -> a -> b
-- > (%~) :: Iso a b c d       -> (c -> d) -> a -> b
-- > (%~) :: Lens a b c d      -> (c -> d) -> a -> b
-- > (%~) :: Traversal a b c d -> (c -> d) -> a -> b
(%~) :: Setting a b c d -> (c -> d) -> a -> b
(%~) = adjust
{-# INLINE (%~) #-}

-- | Replace the target of a 'Lens' or all of the targets of a 'Setter'
-- or 'Traversal' with a constant value.
--
-- This is an infix version of 'set', provided for consistency with '(.=)'
--
--
-- > f <$ a = mapped .~ f $ a
--
-- > ghci> bitAt 0 .~ True $ 0
-- > 1
--
-- > (.~) :: Setter a b c d    -> d -> a -> b
-- > (.~) :: Iso a b c d       -> d -> a -> b
-- > (.~) :: Lens a b c d      -> d -> a -> b
-- > (.~) :: Traversal a b c d -> d -> a -> b
(.~) :: Setting a b c d -> d -> a -> b
(.~) = set
{-# INLINE (.~) #-}

-- | Increment the target(s) of a numerically valued 'Lens', Setter' or 'Traversal'
--
-- > ghci> _1 +~ 1 $ (1,2)
-- > (2,2)
(+~) :: Num c => Setting a b c c -> c -> a -> b
l +~ n = adjust l (+ n)
{-# INLINE (+~) #-}

-- | Multiply the target(s) of a numerically valued 'Lens', 'Iso', 'Setter' or 'Traversal'
--
-- > ghci> _2 *~ 4 $ (1,2)
-- > (1,8)
(*~) :: Num c => Setting a b c c -> c -> a -> b
l *~ n = adjust l (* n)
{-# INLINE (*~) #-}

-- | Decrement the target(s) of a numerically valued 'Lens', 'Iso', 'Setter' or 'Traversal'
--
-- > ghci> _1 -~ 2 $ (1,2)
-- > (-1,2)
(-~) :: Num c => Setting a b c c -> c -> a -> b
l -~ n = adjust l (subtract n)
{-# INLINE (-~) #-}

-- | Divide the target(s) of a numerically valued 'Lens', 'Iso', 'Setter' or 'Traversal'
(//~) :: Fractional c => Setting a b c c -> c -> a -> b
l //~ n = adjust l (/ n)

-- | Logically '||' the target(s) of a 'Bool'-valued 'Lens' or 'Setter'
(||~):: Setting a b Bool Bool -> Bool -> a -> b
l ||~ n = adjust l (|| n)
{-# INLINE (||~) #-}

-- | Logically '&&' the target(s) of a 'Bool'-valued 'Lens' or 'Setter'
(&&~) :: Setting a b Bool Bool -> Bool -> a -> b
l &&~ n = adjust l (&& n)
{-# INLINE (&&~) #-}

-- | Modify the target of a monoidally valued by 'mappend'ing another value.
(<>~) :: Monoid c => Setting a b c c -> c -> a -> b
l <>~ n = adjust l (mappend n)
{-# INLINE (<>~) #-}

------------------------------------------------------------------------------
-- MonadWriter
------------------------------------------------------------------------------

-- | Tell a part of a value to a 'MonadWriter', filling in the rest from 'mempty'
--
-- > whisper l d = tell (set l d mempty)

-- > whisper :: (MonadWriter b m, Monoid a) => Iso a b c d       -> d -> m ()
-- > whisper :: (MonadWriter b m, Monoid a) => Lens a b c d      -> d -> m ()
-- > whisper :: (MonadWriter b m, Monoid a) => Traversal a b c d -> d -> m ()
-- > whisper :: (MonadWriter b m, Monoid a) => Setter a b c d    -> d -> m ()
--
-- > whisper :: (MonadWriter b m, Monoid a) => ((c -> Identity d) -> a -> Identity b) -> d -> m ()
whisper :: (MonadWriter b m, Monoid a) => Setting a b c d -> d -> m ()
whisper l d = tell (set l d mempty)
{-# INLINE whisper #-}

-- | Replace the target of a 'Lens' or all of the targets of a 'Setter' or 'Traversal' in our monadic
-- state with a new value, irrespective of the old.
--
-- > (.=) :: MonadState a m => Iso a a c d             -> d -> m ()
-- > (.=) :: MonadState a m => Lens a a c d            -> d -> m ()
-- > (.=) :: MonadState a m => Traversal a a c d       -> d -> m ()
-- > (.=) :: MonadState a m => Setter a a c d          -> d -> m ()
--
-- "It puts the state in the monad or it gets the hose again."
(.=) :: MonadState a m => Setting a a c d -> d -> m ()
l .= b = State.modify (l .~ b)
{-# INLINE (.=) #-}

-- | Map over the target of a 'Lens' or all of the targets of a 'Setter' or 'Traversal in our monadic state.
--
-- > (%=) :: MonadState a m => Iso a a c d             -> (c -> d) -> m ()
-- > (%=) :: MonadState a m => Lens a a c d            -> (c -> d) -> m ()
-- > (%=) :: MonadState a m => Traversal a a c d       -> (c -> d) -> m ()
-- > (%=) :: MonadState a m => Setter a a c d          -> (c -> d) -> m ()
(%=) :: MonadState a m => Setting a a c d -> (c -> d) -> m ()
l %= f = State.modify (l %~ f)
{-# INLINE (%=) #-}

-- | Modify the target(s) of a 'Simple' 'Lens', 'Iso', 'Setter' or 'Traversal' by adding a value
--
-- Example:
--
-- > fresh = do
-- >   id += 1
-- >   access id
(+=) :: (MonadState a m, Num b) => SimpleSetting a b -> b -> m ()
l += b = State.modify (l +~ b)
{-# INLINE (+=) #-}

-- | Modify the target(s) of a 'Simple' 'Lens', 'Iso', 'Setter' or 'Traversal' by subtracting a value
(-=) :: (MonadState a m, Num b) => SimpleSetting a b -> b -> m ()
l -= b = State.modify (l -~ b)
{-# INLINE (-=) #-}

-- | Modify the target(s) of a 'Simple' 'Lens', 'Iso', 'Setter' or 'Traversal' by multiplying by value
(*=) :: (MonadState a m, Num b) => SimpleSetting a b -> b -> m ()
l *= b = State.modify (l *~ b)
{-# INLINE (*=) #-}

-- | Modify the target(s) of a 'Simple' 'Lens', 'Iso', 'Setter' or 'Traversal' by dividing by a value
(//=) ::  (MonadState a m, Fractional b) => SimpleSetting a b -> b -> m ()
l //= b = State.modify (l //~ b)
{-# INLINE (//=) #-}

-- | Modify the target(s) of a 'Simple' 'Lens', 'Iso', 'Setter' or 'Traversal' by taking their logical '&&' with a value
(&&=):: MonadState a m => SimpleSetting a Bool -> Bool -> m ()
l &&= b = State.modify (l &&~ b)
{-# INLINE (&&=) #-}

-- | Modify the target(s) of a 'Simple' 'Lens', 'Iso, 'Setter' or 'Traversal' by taking their logical '||' with a value
(||=) :: MonadState a m => SimpleSetting a Bool -> Bool -> m ()
l ||= b = State.modify (l ||~ b)
{-# INLINE (||=) #-}

-- | Modify the target(s) of a 'Simple' 'Lens', 'Iso', 'Setter' or 'Traversal' by 'mappend'ing a value.
(<>=) :: (MonadState a m, Monoid b) => SimpleSetting a b -> b -> m ()
l <>= b = State.modify (l <>~ b)
{-# INLINE (<>=) #-}

