{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE UndecidableInstances  #-}

module Language.Nano.Typecheck.Unfold (unfoldFirst, unfoldMaybe, unfoldSafe) where 

import           Text.PrettyPrint.HughesPJ
import           Language.ECMAScript3.PrettyPrint
import qualified Language.Fixpoint.Types as F
import           Language.Fixpoint.Errors
import           Language.Fixpoint.Misc
import           Language.Nano.Types
import           Language.Nano.Errors 
import           Language.Nano.Env
import           Language.Nano.Typecheck.Subst
import           Language.Nano.Typecheck.Types
import           Language.Fixpoint.Parse as P

import           Control.Exception   (throw)
import           Control.Applicative ((<$>))
import qualified Data.HashSet as S
import           Data.List                      (find)
import qualified Data.HashMap.Strict as M 
import           Data.Monoid
import           Text.Parsec

import           Text.Printf 

-----------------------------------------------------------------------------
-- Unfolding ----------------------------------------------------------------
-----------------------------------------------------------------------------

-- | Unfold the FIRST TDef at any part of the type @t@.
-------------------------------------------------------------------------------
unfoldFirst :: (PP r, F.Reftable r) => Env (RType r) -> RType r -> RType r
-------------------------------------------------------------------------------
unfoldFirst env t = go t
  where 
    go (TFun its ot r)         = TFun (appTBi go <$> its) (go ot) r
    go (TObj bs r)             = TObj (appTBi go <$> bs) r
    go (TBd  _)                = errorstar "BUG: unfoldTDefDeep: there should not be a TBody here"
    go (TAnd _)                = errorstar "BUG: unfoldFirst: cannot unfold intersection"
    go (TAll v t)              = TAll v $ go t
    go (TApp (TDef id) acts _) = 
      case envFindTy (F.symbol id) env of
        Just (TBd (TD _ vs bd _ )) -> apply (fromList $ zip vs acts) bd
        _                          -> throw $ errorUnboundId (srcPos id) id
    go (TApp c a r)            = TApp c (go <$> a) r
    go (TArr t r)              = TArr (go t) r
    go t@(TVar _ _ )           = t
    appTBi f (B s t)           = B s $ f t


-- | Unfold a top-level type definition once. 
-- Return @Right t@, where @t@ is the unfolded type if the unfolding is succesful.
-- This includes the case where the input type @t@ is not a type definition in
-- which case the same type is returned.
-- If it is a type literal for which no definition exists return 
-- @Left "<Error message>".
--
-- TODO: Make sure toplevel refinements are the same.
-------------------------------------------------------------------------------
unfoldMaybe :: (PP r, F.Reftable r) => Env (RType r) -> RType r -> Either String (RType r)
-------------------------------------------------------------------------------
unfoldMaybe env t@(TApp (TDef id) acts _) =
      case envFindTy (F.symbol id) env of
        Just (TBd (TD _ vs bd _ )) -> Right $ apply (fromList $ zip vs acts) bd
        _                          -> Left  $ (printf "Failed unfolding: %s" $ ppshow t)
-- The only thing that is unfoldable is a TDef.
-- The rest are just returned as they are.
unfoldMaybe _ t                           = Right t


-- | Force a successful unfolding
-------------------------------------------------------------------------------
unfoldSafe :: (PP r, F.Reftable r) => Env (RType r) -> RType r -> RType r
-------------------------------------------------------------------------------
unfoldSafe env = either error id . unfoldMaybe env


-- Given an environment @γ@, a (string) field @s@ and a type @t@, `getProp` 
-- returns a tuple with elements:
-- ∙ The subtype of @t@ for which the access does not throw an error.
-- ∙ The type the corresponds to the access of exactly that type that does not
--   throw an error.
-------------------------------------------------------------------------------
getProp ::  (IsLocated l, Ord r, PP r, F.Reftable r) => 
  l -> Env (RType r) -> String -> RType r -> Maybe (RType r, RType r)
-------------------------------------------------------------------------------
getProp _ _ s t@(TObj bs _) = 
  do  case find (match $ F.symbol s) bs of
        Just b -> Just (t, b_type b)
        _      -> case find (match $ F.stringSymbol "*") bs of
                    Just b' -> Just (t, b_type b')
                    _       -> Just (t, tUndef)
  where match s (B f _)  = s == f

getProp l γ s t@(TApp _ _ _)  = getPropApp l γ s t 
getProp _ _ _ t@(TFun _ _ _ ) = Just (t, tUndef)
getProp l γ s a@(TArr _ _)    = getPropArr l γ s a
getProp l _ _ t               = die $ bug (srcPos l) $ "getProp: " ++ (ppshow t) 


-------------------------------------------------------------------------------
lookupProto :: (Ord r, PP r, F.Reftable r, IsLocated a) =>
  a -> Env (RType r) -> String -> RType r -> Maybe (RType r, RType r)
-------------------------------------------------------------------------------
lookupProto l γ s t@(TObj bs _) = 
    case find (match $ F.stringSymbol "__proto__") bs of
      Just (B _ t) -> getProp l γ s t
      Nothing -> Just (t, tUndef)
  where match s (B f _)  = s == f
lookupProto l _ _ _ = die $ bug (srcPos l) 
  "lookupProto can only unfold the prototype chain for object types"

getPropApp l γ s t@(TApp c ts _) 
  = case c of 
      TUn      -> getPropUnion l γ s ts
      TInt     -> Just (t, tUndef)
      TBool    -> Just (t, tUndef)
      TString  -> Just (t, tUndef)
      TUndef   -> Nothing
      TNull    -> Nothing
      (TDef _) -> getProp l γ s $ unfoldSafe γ t
      TTop     -> die $ bug (srcPos l) "getProp top"
      TVoid    -> die $ bug (srcPos l) "getProp void"

getPropArr l γ s a@(TArr _ _) 
  = case s of
    -- TODO: make more specific, add refinements 
    "length" -> Just (a, tInt) 
    _        -> case stringToInt s of
                  -- Implicit coersion of numieric strings:
                  -- x["0"] = x[0], x["1"] = x[1], etc.
                  Just i  -> getIdx l γ i a 
                  -- The rest of the cases are undefined
                  Nothing -> Just (a, tUndef) 

-------------------------------------------------------------------------------
stringToInt :: String -> Maybe Int
-------------------------------------------------------------------------------
stringToInt s = 
  case runParser P.integer 0 "" s of
    Right i -> Just $ fromInteger i
    Left _  -> Nothing


-- Accessing the @x@ field of the union type with @ts@ as its parts, returns
-- "Nothing" if accessing all parts return error, or "Just (ts, tfs)" if
-- accessing @ts@ returns type @tfs@. @ts@ is useful for adding casts later on.
-------------------------------------------------------------------------------
getPropUnion :: (IsLocated l, Ord r, PP r, F.Reftable r) 
             => l -> Env (RType r) -> String -> [RType r] -> Maybe (RType r, RType r)
-------------------------------------------------------------------------------
getPropUnion l γ f ts = 
  -- Gather all the types that do not throw errors, and the type of 
  -- the accessed expression that yields them
  case [tts | Just tts <- getProp l γ f <$> ts] of
    [] -> Nothing
    ts -> Just $ mapPair mkUnion $ unzip ts


-------------------------------------------------------------------------------
getIdx ::  (IsLocated l, Ord r, PP r, F.Reftable r) => 
  l -> Env (RType r) -> Int -> RType r -> Maybe (RType r, RType r)
-------------------------------------------------------------------------------
getIdx _ _ _ a@(TArr t _)  = Just (a,t)
getIdx l γ i t             = getProp l γ (show i) t 
--error $ "Unimplemented: getIdx on" ++ (ppshow t) 


