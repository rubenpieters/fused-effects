{-# LANGUAGE DeriveFunctor, ExistentialQuantification, FlexibleContexts, FlexibleInstances, GeneralizedNewtypeDeriving, LambdaCase, MultiParamTypeClasses, RankNTypes, StandaloneDeriving, TypeOperators, UndecidableInstances #-}
module Control.Effect.Resource
( Resource(..)
, bracket
, bracketOnError
, finally
, onException
, runResource
, ResourceC(..)
) where

import           Control.Effect.Carrier
import           Control.Effect.Internal
import           Control.Effect.Reader
import           Control.Effect.Sum
import qualified Control.Exception as Exc
import           Control.Monad.Fail
import           Control.Monad.IO.Class

data Resource m k
  = forall resource any output . Resource (m resource) (resource -> m any) (resource -> m output) (output -> k)
  | forall resource any output . OnError  (m resource) (resource -> m any) (resource -> m output) (output -> k)

deriving instance Functor (Resource m)

instance HFunctor Resource where
  hmap f (Resource acquire release use k) = Resource (f acquire) (f . release) (f . use) k
  hmap f (OnError acquire release use k)  = OnError  (f acquire) (f . release) (f . use) k

instance Effect Resource where
  handle state handler (Resource acquire release use k) = Resource (handler (acquire <$ state)) (handler . fmap release) (handler . fmap use) (handler . fmap k)
  handle state handler (OnError acquire release use k)  = OnError  (handler (acquire <$ state)) (handler . fmap release) (handler . fmap use) (handler . fmap k)

-- | Provides a safe idiom to acquire and release resources safely.
--
-- When acquiring and operating on a resource (such as opening and
-- reading file handle with 'openFile' or writing to a blob of memory
-- with 'malloc'), any exception thrown during the operation may mean
-- that the resource is not properly released. @bracket acquire release op@
-- ensures that @release@ is run on the value returned from @acquire@ even
-- if @op@ throws an exception.
--
-- 'bracket' is safe in the presence of asynchronous exceptions.
bracket :: (Member Resource sig, Carrier sig m)
        => m resource           -- ^ computation to run first ("acquire resource")
        -> (resource -> m any)  -- ^ computation to run last ("release resource")
        -> (resource -> m a)    -- ^ computation to run in-between
        -> m a
bracket acquire release use = send (Resource acquire release use ret)

-- | Like 'bracket', but only performs the final action if there was an
-- exception raised by the in-between computation.
bracketOnError :: (Member Resource sig, Carrier sig m)
               => m resource           -- ^ computation to run first ("acquire resource")
               -> (resource -> m any)  -- ^ computation to run last ("release resource")
               -> (resource -> m a)    -- ^ computation to run in-between
               -> m a
bracketOnError acquire release use = send (OnError acquire release use ret)

-- | Like 'bracket', but for the simple case of one computation to run afterward.
finally :: (Member Resource sig, Carrier sig m, Applicative m)
        => m a -- ^ computation to run first
        -> m b -- ^ computation to run afterward (even if an exception was raised)
        -> m a
finally act end = bracket (pure ()) (const end) (const act)

-- | Like 'bracketOnError', but for the simple case of one computation to run afterward.
onException :: (Member Resource sig, Carrier sig m, Applicative m)
        => m a -- ^ computation to run first
        -> m b -- ^ computation to run afterward if an exception was raised
        -> m a
onException act end = bracketOnError (pure ()) (const end) (const act)

runResource :: (Carrier sig m, MonadIO m)
            => (forall x . m x -> IO x)
            -> Eff (ResourceC m) a
            -> m a
runResource handler = flip runReaderC (Handler handler) . runResourceC . interpret

newtype ResourceC m a = ResourceC { runResourceC :: ReaderC (Handler m) m a }
  deriving (Applicative, Functor, Monad, MonadFail, MonadIO)

newtype Handler m = Handler (forall x . m x -> IO x)

runHandler :: Handler m -> ResourceC m a -> IO a
runHandler h@(Handler handler) = handler . flip runReaderC h . runResourceC

instance (Carrier sig m, MonadIO m) => Carrier (Resource :+: sig) (ResourceC m) where
  ret = pure
  eff = handleSum
    (ResourceC . eff . R . handleCoercible)
    (\case
        Resource acquire release use k -> do
          handler <- ResourceC ask
          a <- liftIO (Exc.bracket
            (runHandler handler acquire)
            (runHandler handler . release)
            (runHandler handler . use))
          k a
        OnError acquire release use k -> do
          handler <- ResourceC ask
          a <- liftIO (Exc.bracketOnError
            (runHandler handler acquire)
            (runHandler handler . release)
            (runHandler handler . use))
          k a)
