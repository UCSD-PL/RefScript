{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE ConstraintKinds       #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE UndecidableInstances  #-}

module Language.Nano.Typecheck.Unify ( 
  
  -- * Unification 
  unifys

  ) where 

import           Language.Fixpoint.Misc
import           Language.Fixpoint.Errors 
import qualified Language.Fixpoint.Types      as F

import           Language.Nano.Annots
import           Language.Nano.Errors 
import           Language.Nano.Locations
import           Language.Nano.Pretty
import           Language.Nano.Types
import           Language.Nano.Typecheck.Environment
import           Language.Nano.Typecheck.Types
import           Language.Nano.Typecheck.Resolve
import           Language.Nano.Typecheck.Subst
import           Language.Nano.Typecheck.Sub

import           Data.Generics
import           Data.Either                     (rights)
import           Data.Maybe                      (maybeToList)
import qualified Data.List                    as L
import qualified Data.HashSet                 as S
import qualified Data.HashMap.Strict          as HM 
import qualified Data.Map.Strict              as M
import           Data.Monoid
import           Control.Monad                   (foldM)
import           Data.Function                   (on)

-- import           Debug.Trace

-----------------------------------------------------------------------------
-- | Unification
-----------------------------------------------------------------------------

type Unif r = (PP r, F.Reftable r, ExprReftable F.Symbol r, ExprReftable Int r, Free (Fact r))

-----------------------------------------------------------------------------
unify :: (Unif r) 
      => SrcSpan 
      -> TCEnv r
      -> RSubst r 
      -> RType r 
      -> RType r 
      -> Either Error (RSubst r)
-----------------------------------------------------------------------------
unify l _ θ (TVar α _) (TVar β _) = varEql l θ α β 
unify l _ θ (TVar α _) t'         = varAsn l θ α t'
unify l _ θ t          (TVar α _) = varAsn l θ α t

-- XXX: ORDERING IMPORTANT HERE
-- Keep the union case before unfolding, but after type variables

unify l γ θ t t' 
  | any isTUnion [t,t'] 
  = unifyUnions l γ θ t t'

unify l γ θ (TFun t1s o1 _) (TFun t2s o2 _)
  = unifys l γ θ (o1 : map b_type t1s') (o2 : map b_type t2s')
  where 
    (t1s',t2s') = unzip $ zip t1s t2s -- get their common parts

unify l γ θ (TRef (Gen x1 t1s) _) (TRef (Gen x2 t2s) _) 
  | x1 == x2
  = unifys l γ θ t1s t2s
  | isAncestor γ x1 x2 || isAncestor γ x2 x1       
  = case (weaken γ (Gen x1 t1s) x2, weaken γ (Gen x2 t2s) x1) of
      -- Adjusting `t1` to reach `t2` moving upward in the type hierarchy (Upcast)
      (Just (Gen _ t1s'), _) -> unifys l γ θ t1s' t2s
      -- Adjusting `t2` to reach `t1` moving upward in the type hierarchy (DownCast)
      (_, Just (Gen _ t2s')) -> unifys l γ θ t1s t2s'
      (_, _) -> Left $ bugWeakenAncestors (srcPos l) x1 x2

unify l γ θ (TType k1 (Gen n1 t1s)) (TType k2 (Gen n2 t2s)) 
  | k1 == k2, n1 == n2 
  = unifys l γ θ t1s t2s

-- "Object"-ify types that can be expanded to an object literal type
unify l γ θ t1 t2 
  | all maybeTObj [t1,t2]
  , Just (TObj m1 _) <- expandType NonCoercive γ t1
  , Just (TObj m2 _) <- expandType NonCoercive γ t2
  = unifyMembers l γ θ m1 m2
   
-- The rest of the cases do not cause any unification.
unify _ _ θ _  _ = return θ

-----------------------------------------------------------------------------
unifyUnions :: Unif r
            => SrcSpan
            -> TCEnv r
            -> RSubst r
            -> RType r
            -> RType r
            -> Either Error (RSubst r)
-----------------------------------------------------------------------------
unifyUnions l γ θ t1 t2 
  | [v1] <- v1s
  , [  ] <- v2s
  = unify l γ θ v1 (mkUnion unmatched2) >>= \θ1 -> 
    unifys l γ θ1 c1s' c2s'
  | [  ] <- v1s
  , [v2] <- v2s
  = unify l γ θ (mkUnion unmatched1) v2 >>= \θ1 -> 
     unifys l γ θ1 c1s' c2s'
  | [v1] <- v1s
  , [v2] <- v2s 
  = unify l γ θ  v1 (mkUnion unmatched2) >>= \θ1 -> 
    unify l γ θ1 (mkUnion unmatched1) v2 >>= \θ2 -> 
    unifys l γ θ2 c1s' c2s'
  | length v1s > 1  
  = Left $ unsupportedUnionTVar (srcPos l) t1  
  | otherwise 
  = Left $ unsupportedUnionTVar (srcPos l) t2 
  where
    (t1s, t2s)   = mapPair bkUnion (t1, t2)
    (v1s,c1s)    = L.partition isTVar t1s
    (v2s,c2s)    = L.partition isTVar t2s
    (c1s', c2s') = unzip [ (c1, c2) | c1 <- c1s, c2 <- c2s, c1 `match` c2 ]    
    unmatched1   = [ c1 | c1 <- c1s, not $ any (match c1) c2s, nonTriv c1 ]
    unmatched2   = [ c2 | c2 <- c2s, not $ any (match c2) c1s, nonTriv c2 ]
    nonTriv t    = not (isTNull t) && not (isTUndef t)

    match (TPrim p1 _)          (TPrim p2 _)          = p1 == p2 
    match (TVar v1 _)           (TVar v2 _)           = v1 == v2
    match (TRef (Gen n1 _) _)   (TRef (Gen n2 _) _)   = n1 == n2
    match (TObj _ _ )           (TObj _ _)            = True 
    match (TType k1 (Gen n1 _)) (TType k2 (Gen n2 _)) = k1 == k2 && n1 == n2
    match (TMod m1)             (TMod m2)             = m1 == m2
    match (TFun _ _ _)          (TFun _ _ _)          = True 
    match _                     _                     = False

-----------------------------------------------------------------------------
unifyMembers :: Unif r 
             => SrcSpan 
             -> TCEnv r 
             -> RSubst r 
             -> TypeMembers r 
             -> TypeMembers r 
             -> Either Error (RSubst r)
-----------------------------------------------------------------------------
unifyMembers l γ θ (TM p1 m1 _ _ c1 k1 s1 n1) (TM p2 m2 _ _ c2 k2 s2 n2) = 
    unifys l γ θ p1s  p2s >>= \θ1 ->
    unifys l γ θ1 m1s m2s >>= \θ2 -> 
    unifys l γ θ2 r1s r2s   
  where
    (p1s , p2s) = unzip $ concatMap fromFI $ F.toListSEnv $ F.intersectWithSEnv (,) p1 p2
    (m1s , m2s) = unzip $ concatMap fromMI $ F.toListSEnv $ F.intersectWithSEnv (,) m1 m2

    fromFI (_, (FI _ t1 t2, FI _ t1' t2')) = [(t1, t1'), (t2, t2')]
    fromMI (_, (MI _ _  t2, MI _ _   t2')) = [(t2, t2')]
    fromBoth (Just a1, Just a2)  = [(a1,a2)]
    fromBoth _                   = []
    (r1s, r2s)  = unzip $ concatMap fromBoth [(c1,c2),(k1,k2),(n1,n2)]
   
-----------------------------------------------------------------------------
unifys :: Unif r
       => SrcSpan 
       -> TCEnv r 
       -> RSubst r 
       -> [RType r] -> [RType r] 
       -> Either Error (RSubst r)
-----------------------------------------------------------------------------
unifys l γ θ ts ts'  
  | nTs == nTs'   
  = foldM foo θ $ zip ts ts'
  | otherwise 
  = Left $ errorUnification l ts ts'
  where 
    (nTs, nTs')   = mapPair length (ts, ts')
    foo θ (t, t') = unify l γ θ (apply θ t) (apply θ t')

-----------------------------------------------------------------------------
varEql :: Unif r => SrcSpan -> RSubst r -> TVar -> TVar -> Either Error (RSubst r)
-----------------------------------------------------------------------------
varEql l θ α β =  
  case varAsn l θ α $ tVar β of
    Right θ' -> Right θ'
    Left  s1 -> 
      case varAsn l θ β $ tVar α of
        Right θ'' -> Right θ''
        Left  s2  -> Left $ catMessage s1 (errMsg s2) 

-----------------------------------------------------------------------------
varAsn ::  Unif r => SrcSpan -> RSubst r -> TVar -> RType r -> Either Error (RSubst r)
-----------------------------------------------------------------------------
varAsn l θ α t 
  | on eqV toType t (apply θ (tVar α))     = Right $ θ 
  | on eqV toType (tVar α) `any` bkUnion t = Right $ θ 
  | α `S.member` free t                    = Left  $ errorOccursCheck l α t 
  | unassigned α θ                         = Right $ θ `mappend` (Su $ HM.singleton α t)
  | otherwise                              = Left  $ errorRigidUnify l α (toType t)

unassigned α (Su m) | Just t <- HM.lookup α m = t `eqV` TVar α ()
                    | otherwise               = False

