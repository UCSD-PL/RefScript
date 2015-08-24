{-# LANGUAGE ConstraintKinds       #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TupleSections         #-}
{-# LANGUAGE UndecidableInstances  #-}

module Language.Nano.Lookup (
    getProp
  , extractCall
  , extractCtor
  , AccessKind(..)
  ) where

import           Control.Applicative           (pure, (<$>))
import           Data.Generics
import qualified Data.Map.Strict               as M
import qualified Language.Fixpoint.Bitvector   as BV
import qualified Language.Fixpoint.Types       as F
import           Language.Nano.AST
import           Language.Nano.ClassHierarchy
import           Language.Nano.Core.Env
import           Language.Nano.Environment
import           Language.Nano.Errors
import           Language.Nano.Names
import           Language.Nano.Pretty
import           Language.Nano.Typecheck.Subst
import           Language.Nano.Typecheck.Types
import           Language.Nano.Types

-- import           Debug.Trace


-- | Excluded fields from string index lookup
--
excludedFieldSymbols = F.symbol <$> [ "hasOwnProperty", "prototype", "__proto__" ]

type PPRD r = (ExprReftable F.Symbol r, ExprReftable Int r, PP r, F.Reftable r, Data r)

data AccessKind = MethodAccess | FieldAccess

instance PP AccessKind where
  pp MethodAccess = pp "MethodAccess"
  pp FieldAccess  = pp "FieldAccess"


-- | `getProp γ b x s t` performs the access `x.f`, where @t@ is the type
-- assigned to @x@ and returns a triplet containing:
--  (a) the subtype of @t@ for which the access of field @f@ is successful,
--  (b) the accessed type, and
--  [ (c) the mutability associcated with the accessed element ]
--
-------------------------------------------------------------------------------
getProp :: (PPRD r, EnvLike r g, F.Symbolic f, PP f)
        => g r -> AccessKind -> StaticKind -> f -> RType r -> Maybe (RType r, RType r)
-------------------------------------------------------------------------------
getProp γ b s f t@(TPrim _ _) = getPropPrim γ b s f t

getProp γ b s f (TOr ts) = getPropUnion γ b s f ts

-- | TODO: Chain up to 'Object'
getProp γ b s f t@(TObj es _)
  = (t,) <$> accessMember γ b s f es -- `M.union` t_elts empty
  -- where
  --   emptyObjectInterface = undefined

-- | Enumeration
-- FIXME: Instead of the actual integer value, assign unique symbolic values:
--        E.g. A_B_C_1 ...
getProp γ b s f t@(TRef (Gen n []) _)
  | Just e  <- resolveEnumInEnv γ n
  , Just io <- envFindTy f $ e_mapping e
  = case io of
      IntLit _ i -> return (t, tNum `strengthen` exprReft i)
      -- XXX : is 32-bit going to be enough ???
      -- XXX: Invalid BV values will be dropped
      HexLit _ s -> bitVectorValue s >>= return . (t,) . (tBV32 `strengthen`)
      _          -> Nothing

getProp γ b _ f t@(TRef _ _)
  = expandType Coercive (cha γ) t >>= getProp γ b InstanceK f

getProp γ b s f t@(TClass _)
  = expandType Coercive (cha γ) t >>= getProp γ b StaticK f

getProp γ _ s f t@(TMod m)
  = do  m'        <- resolveModuleInEnv γ m
        VI _ _ t' <- envFindTy f $ m_variables m'
        return     $ (t,t')

getProp _ _ _ _ _ = Nothing


-------------------------------------------------------------------------------
-- getPropPrim :: (PPRD r, EnvLike r g, F.Symbolic f, PP f)
--            => g r
--            -> AccessKind
--            -> f
--            -> RType r
--            -> Maybe (RType r, RType r, Mutability)
-------------------------------------------------------------------------------
getPropPrim γ b s f t@(TPrim c _) =
  case c of
    TBoolean   -> Nothing
    TUndefined -> Nothing
    TNull      -> Nothing
    TNumber    -> (t,) <$> lookupAmbientType γ b f "Number"
    TString    -> (t,) <$> lookupAmbientType γ b f "String"
    TStrLit _  -> (t,) <$> lookupAmbientType γ b f "String"
    TBV32      -> (t,) <$> lookupAmbientType γ b f "Number"
    TTop       -> Nothing
    TVoid      -> Nothing
    TTop       -> Nothing
    TBot       -> Nothing
    TFPBool    -> Nothing
getPropPrim _ _ _ _ _ = error "getPropPrim should only be applied to TApp"


-- | `extractCtor γ t` extracts a contructor signature from a type @t@
--
-- TODO: Is fixRet necessary?
--
-------------------------------------------------------------------------------
extractCtor :: (PPRD r, EnvLike r g) => g r -> RType r -> Maybe (RType r)
-------------------------------------------------------------------------------
extractCtor γ t = go t
  where
    -- No need to parents of class A, cause A will have a constructor in any case
    -- e.g. class A extends B { .. }
    go (TClass (BGen x _)) | Just (TD (TS _ (BGen _ bs) _) ms) <- resolveTypeInEnv γ x
                           = tm_ctor ms >>= pure . mkAll bs
    -- interface IA<V extends T> { new(x: T) { ... } }
    -- var a: IA<S>;  // S <: T
    -- var x = new a(x);
    go (TRef _ _)          = expandType Coercive (cha γ) t >>= go
    go (TObj ms _)         = tm_ctor ms
    go _                   = Nothing

-- fixRet x vs = fmap (mkAnd . (mkAll vs . mkFun . fixOut vs <$>)) . bkFuns
--   where fixOut vs (a,b,_) = (a,b,retT x vs)

-- retT x vs  = TRef (Gen x (tVar <$> vs)) fTop
-- defCtor x vs = mkAll vs $ TFun Nothing [] (retT x vs) fTop

-------------------------------------------------------------------------------
extractCall :: (EnvLike r g, PPRD r) => g r -> RType r -> [RType r]
-------------------------------------------------------------------------------
extractCall γ t          = uncurry mkAll <$> go [] t
  where
    go αs t@(TFun _ _ _) = [(αs, t)]
    go αs   (TAnd ts)    = concatMap (go αs) ts
    go αs   (TAll α t)   = go (αs ++ [α]) t
    go αs t@(TRef _ _)   | Just t' <- expandType Coercive (cha γ) t
                         = go αs t'
    go αs   (TObj ms _)  | Just t <- tm_call ms
                         = go αs t
    go _  _              = []

-------------------------------------------------------------------------------
accessMember :: (PPRD r, EnvLike r g, F.Symbolic f, PP f)
             => g r -> AccessKind -> StaticKind -> f -> TypeMembers r -> Maybe (RType r)
-------------------------------------------------------------------------------
accessMember γ b@MethodAccess StaticK m ms
  | Just (MI _ _ t) <- F.lookupSEnv (F.symbol m) $ tm_smeth ms
  = Just t
  | otherwise
  = Nothing
accessMember γ b@MethodAccess InstanceK m ms
  | Just (MI _ _ t) <- F.lookupSEnv (F.symbol m) $ tm_meth ms
  = Just t
  | otherwise
  = Nothing

accessMember γ b@FieldAccess StaticK f ms
  | Just f@(FI o _ t) <- F.lookupSEnv (F.symbol f) $ tm_sprop ms
  = if o == Opt then Just $ orUndef t
                else Just $ t
  | Just t <- tm_sidx ms
  , validFieldName f
  = Just t
  -- | otherwise
  -- = accessMemberProto γ b sk f es

-- accessMemberProto γ b sk f es
--   | Just (FieldSig _ _ _ pt) <- M.lookup (F.symbol "__proto__",sk) es
--   , Just (_,t,m) <- getProp γ b f pt
--   = return (t,m)
--   | otherwise
--   = Nothing

-------------------------------------------------------------------------------
validFieldName  :: F.Symbolic f => f -> Bool
-------------------------------------------------------------------------------
validFieldName f = not $ F.symbol f `elem` excludedFieldSymbols

-------------------------------------------------------------------------------
lookupAmbientType :: (PPRD r, EnvLike r g, F.Symbolic f, F.Symbolic s, PP f)
                  => g r -> AccessKind -> f -> s -> Maybe (RType r)
-------------------------------------------------------------------------------
lookupAmbientType γ b f amb
  = resolveTypeInEnv γ nm >>= \(TD _ ms) ->
    accessMember γ b InstanceK f ms
  where
    nm = mkAbsName [] (F.symbol amb)

-- | Accessing the @f@ field of the union type with @ts@ as its parts, returns
-- "Nothing" if accessing all parts return error, or "Just (ts, tfs)" if
-- accessing @ts@ returns type @tfs@. @ts@ is useful for adding casts later on.
-------------------------------------------------------------------------------
getPropUnion :: (PPRD r, EnvLike r g, F.Symbolic f, PP f)
             => g r -> AccessKind -> StaticKind -> f -> [RType r] -> Maybe (RType r, RType r)
-------------------------------------------------------------------------------
getPropUnion γ b s f ts =
  case unzip [ ts' | Just ts' <- getProp γ b s f <$> ts] of
    ([],[]) -> Nothing
    (t1s,t2s) -> Just (mkUnion t1s, mkUnion t2s)

