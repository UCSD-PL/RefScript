{-# LANGUAGE TypeSynonymInstances      #-}
{-# LANGUAGE ConstraintKinds           #-}
{-# LANGUAGE FlexibleContexts          #-}
{-# LANGUAGE TupleSections             #-}
{-# LANGUAGE FlexibleInstances         #-}
{-# LANGUAGE DoAndIfThenElse           #-}
{-# LANGUAGE NoMonomorphismRestriction #-}

-- | Operations pertaining to Constraint Generation

module Language.Nano.Liquid.CGMonad (
    
  -- * Constraint Generation Monad
    CGM

  -- * Constraint Information
  , CGInfo (..)

  -- * Execute Action and Get FInfo
  , getCGInfo 

  -- * Get Defined Function Type Signature
  , getDefType, getDef, getPropTDefM, getPropM

  -- * Throw Errors
  , cgError      

  -- * Fresh Templates for Unknown Refinement Types 
  , freshTyFun, freshTyVar, freshTyInst, freshTyPhis
  , freshTyPhisWhile, freshTyObj

  -- * Freshable
  , Freshable (..)

  -- * Environment API
  , envAddFresh, envAdds, envAddReturn, envAddGuard, envFindTy, envFindAnnot
  , envRemSpec, isGlobalVar, envToList, envFindReturn, envPushContext
  , envGetContextCast, envGetContextTypArgs

  , findSymM, findSymOrDieM

  -- * Add Subtyping Constraints
  , subType, wellFormed
  
  -- * Add Type Annotations
  , addAnnot


  -- * Function Types
  , cgFunTys

  -- * This
  , cgPeekThis, cgWithThis

  -- * Super 
  , getSuperM, getSuperDefM


  ) where

import           Data.Maybe                     (fromMaybe, listToMaybe, catMaybes, isJust)
import           Data.Monoid                    (mempty)
import qualified Data.HashMap.Strict            as M
import qualified Data.List                      as L
import           Data.Function                  (on)
import           Text.PrettyPrint.HughesPJ
import           Language.Nano.Types
import           Language.Nano.Errors
import qualified Language.Nano.Annots           as A
import qualified Language.Nano.Env              as E
import           Language.Nano.Typecheck.Types 
import           Language.Nano.Typecheck.Lookup
import           Language.Nano.Typecheck.Subst
import           Language.Nano.Liquid.Types
import           Language.Nano.Liquid.Qualifiers


import qualified Language.Fixpoint.Types as F
import           Language.Fixpoint.Misc
import           Language.Fixpoint.Errors
import           Control.Applicative 
import           Control.Exception (throw)

import           Control.Monad
import           Control.Monad.State
import           Control.Monad.Error hiding (Error)
import           Text.Printf 

import           Language.ECMAScript3.Syntax
import           Language.ECMAScript3.PrettyPrint

-- import           Debug.Trace                        (trace)

-------------------------------------------------------------------------------
-- | Top level type returned after Constraint Generation
-------------------------------------------------------------------------------

data CGInfo = CGI { cgi_finfo :: F.FInfo Cinfo
                  , cgi_annot :: A.UAnnInfo RefType  
                  }

-- Dump the refinement subtyping constraints
instance PP CGInfo where
  pp (CGI finfo _) = cat (map pp (M.elems $ F.cm finfo))

instance PP (F.SubC c) where
  pp s = pp (F.lhsCs s) <+> text " <: " <+> pp (F.rhsCs s)


-------------------------------------------------------------------------------
getCGInfo :: Config -> NanoRefType -> CGM a -> CGInfo
-------------------------------------------------------------------------------
getCGInfo cfg pgm = cgStateCInfo pgm . execute cfg pgm . (>> fixCWs)
  where 
    fixCWs       = (,) <$> fixCs <*> fixWs
    fixCs        = get >>= concatMapM splitC . cs
    fixWs        = get >>= concatMapM splitW . ws

execute :: Config -> NanoRefType -> CGM a -> (a, CGState)
execute cfg pgm act
  = case runState (runErrorT act) $ initState cfg pgm of 
      (Left err, _) -> throw err
      (Right x, st) -> (x, st)  

initState       :: Config -> Nano AnnTypeR RefType -> CGState
initState c p   = CGS F.emptyBindEnv (specs p) (defs p) (externs p) [] [] 0 mempty invs c [this] 
  where 
    invs        = M.fromList [(tc, t) | t@(Loc _ (TApp tc _ _)) <- invts p]
    this        = tTop

getDefType f 
  = do m <- cg_sigs <$> get
       maybe err return $ E.envFindTy f m 
    where 
       err = cgError l $ errorMissingSpec l f
       l   = srcPos f

-- cgStateFInfo :: Nano a1 (RType F.Reft)-> (([F.SubC Cinfo], [F.WfC Cinfo]), CGState) -> CGInfo
cgStateCInfo pgm ((fcs, fws), cg) = CGI (patchSymLits fi) (cg_ann cg)
  where 
    fi   = F.FI { F.cm    = M.fromList $ F.addIds fcs  
                , F.ws    = fws
                , F.bs    = clear $ binds cg
                , F.gs    = clear $ measureEnv pgm
                , F.lits  = []
                , F.kuts  = F.ksEmpty
                , F.quals = clear $ nanoQualifiers pgm 
                }

patchSymLits fi = fi { F.lits = clear $ F.symConstLits fi ++ F.lits fi }


-- | Get binding from object type

---------------------------------------------------------------------------------------
measureEnv   ::  Nano a (RType F.Reft) -> F.SEnv F.SortedReft
---------------------------------------------------------------------------------------
measureEnv   = fmap rTypeSortedReft . E.envSEnv . consts 

---------------------------------------------------------------------------------------
-- | Constraint Generation Monad 
---------------------------------------------------------------------------------------

data CGState 
  = CGS { binds    :: F.BindEnv            -- ^ global list of fixpoint binders
        , cg_sigs  :: !(E.Env RefType)     -- ^ type sigs for all defined functions
        , cg_defs  :: !(TDefEnv RefType)   -- ^ defined types 
        , cg_ext   :: !(E.Env RefType)     -- ^ Extern (unchecked) declarations
        , cs       :: ![SubC]              -- ^ subtyping constraints
        , ws       :: ![WfC]               -- ^ well-formedness constraints
        , count    :: !Integer             -- ^ freshness counter
        , cg_ann   :: A.UAnnInfo RefType   -- ^ recorded annotations
        , invs     :: TConInv              -- ^ type constructor invariants
        , cg_opts  :: Config               -- ^ configuration options
        , cg_this  :: ![RefType]           -- ^ a stack holding types for 'this' 
        }

type CGM     = ErrorT Error (State CGState)

type TConInv = M.HashMap TCon (Located RefType)


-------------------------------------------------------------------------------
getDef  :: CGM (TDefEnv RefType)
-------------------------------------------------------------------------------
getDef = cg_defs <$> get

-- XXX: This is not really used 
-------------------------------------------------------------------------------
getExts  :: CGM (E.Env RefType)
-------------------------------------------------------------------------------
getExts = cg_ext <$> get


getPropTDefM b l s t ts = do 
  δ <- getDef 
  return $ getPropTDef b l δ (F.symbol s) ts t

getPropM b l s t = do 
  (δ, ε) <- (,) <$> getDef <*> getExts
  return  $ snd <$> getProp l ε δ (F.symbol s) t

---------------------------------------------------------------------------------------
cgError     :: a -> Error -> CGM b 
---------------------------------------------------------------------------------------
cgError _ e = throwError e

---------------------------------------------------------------------------------------
-- | Environment API
---------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------
envPushContext :: (CallSite a) => a -> CGEnv -> CGEnv
---------------------------------------------------------------------------------------
envPushContext c g = g {cge_ctx = pushContext c (cge_ctx g)}

---------------------------------------------------------------------------------------
envGetContextCast :: CGEnv -> AnnTypeR -> Cast F.Reft
---------------------------------------------------------------------------------------
envGetContextCast g a 
  = case [c | TCast cx c <- ann_fact a, cx == cge_ctx g] of
      [ ] -> CNo
      [c] -> c
      cs  -> die $ errorMultipleCasts (srcPos a) cs

---------------------------------------------------------------------------------------
envGetContextTypArgs :: CGEnv -> AnnTypeR -> [TVar] -> [RefType]
---------------------------------------------------------------------------------------
-- NOTE: If we do not need to instantiate any type parameter (i.e. length αs ==
-- 0), DO NOT attempt to compare that with the TypInst that might hide withing
-- the expression, cause those type instantiations might serve anothor reason
-- (i.e. might be there for a separate instantiation).  
envGetContextTypArgs _ _ []        = []
envGetContextTypArgs g a αs
  = case [i | TypInst ξ' i <- ann_fact a, ξ' == cge_ctx g] of 
      [i] | length i == length αs -> i 
      _                           -> die $ bugMissingTypeArgs $ srcPos a


---------------------------------------------------------------------------------------
envAddFresh :: (IsLocated l) => String -> l -> RefType -> CGEnv -> CGM (Id AnnTypeR, CGEnv) 
---------------------------------------------------------------------------------------
envAddFresh _ l t g 
  = do x  <- freshId loc
       g' <- envAdds [(x, t)] g
       addAnnot (srcPos l) x t
       return (x, g')
    where loc = srcPos l
   
freshId l = Id (Ann l []) <$> fresh


---------------------------------------------------------------------------------------
envAdds      :: (F.Symbolic x, IsLocated x) => [(x, RefType)] -> CGEnv -> CGM CGEnv
---------------------------------------------------------------------------------------
envAdds xts' g
  = do xts    <- zip xs  <$> mapM addInvariant ts
       is     <- forM xts $  addFixpointBind 
       _      <- forM xts $  \(x, t) -> addAnnot (srcPos x) x t
       return  $ g { renv = E.envAdds xts        (renv g) } 
                   { fenv = F.insertsIBindEnv is (fenv g) }
    where 
       (xs,ts) = unzip xts'


---------------------------------------------------------------------------------------
addFixpointBind :: (F.Symbolic x) => (x, RefType) -> CGM F.BindId
---------------------------------------------------------------------------------------
addFixpointBind (x, t) 
  = do let s     = F.symbol x
       let r     = rTypeSortedReft t
       (i, bs') <- F.insertBindEnv s r . binds <$> get 
       modify    $ \st -> st { binds = bs' }
       return    $ i

---------------------------------------------------------------------------------------
addInvariant   :: RefType -> CGM RefType
---------------------------------------------------------------------------------------
addInvariant t           = ((`tx` t) . invs) <$> get
  where 
    tx i t@(TApp tc _ o) = maybe t (\i -> strengthenOp t o $ rTypeReft $ val i) $ M.lookup tc i
    tx _ t               = t 

    strengthenOp t o r   | L.elem r (ofRef o) = t
    strengthenOp t _ r   | otherwise          = strengthen t r

    ofRef (F.Reft (s, as)) = (F.Reft . (s,) . single) <$> as


---------------------------------------------------------------------------------------
addAnnot       :: (F.Symbolic x) => SourceSpan -> x -> RefType -> CGM () 
---------------------------------------------------------------------------------------
addAnnot l x t = modify $ \st -> st {cg_ann = A.addAnnot l x t (cg_ann st)}

---------------------------------------------------------------------------------------
envAddReturn        :: (IsLocated f)  => f -> RefType -> CGEnv -> CGEnv 
---------------------------------------------------------------------------------------
envAddReturn f t g  = g { renv = E.envAddReturn f t (renv g) } 

---------------------------------------------------------------------------------------
envAddGuard       :: (F.Symbolic x, IsLocated x) => x -> Bool -> CGEnv -> CGEnv  
---------------------------------------------------------------------------------------
envAddGuard x b g = g { guards = guard b x : guards g }
  where 
    guard True    = F.eProp 
    guard False   = F.PNot . F.eProp


-- | A helper that returns the actual @RefType@ of the expression by looking up
--   the environment with the name. Interstring cases:
--   
--   * Global variables (that can still be assigned) should not be strengthened
--     with single.
--   * The search includes classes, as they might contain static fields.
--   * Local (non-assignable) variables are strengthened with singleton for 
--     base-types.
---------------------------------------------------------------------------------------
-- envFindTy     :: (IsLocated x, F.Symbolic x, F.Expression x) => x -> CGEnv -> RefType 
---------------------------------------------------------------------------------------
envFindTy msg x g = fromMaybe err $ listToMaybe $ catMaybes [globalSpec, staticField, local]
  where 
    -- Check for global spec
    globalSpec  | isJust $ E.envFindTy x $ cge_spec g = E.envFindTy x $ renv g
                | otherwise                           = Nothing
    -- Check for static fields
    staticField = case findSym x $ cge_defs g of    
        Just t  | t_class t -> Just $ TApp (TRef (F.symbol x, True)) [] fTop
        _                   -> Nothing 
    -- Check for local variable
    local       = fmap (`eSingleton` x) $ E.envFindTy x $ renv g
    err         = throw $ bugUnboundVariable (srcPos x) msg (F.symbol x) 


envFindAnnot l x g = E.envFindTy x $ renv g

envRemSpec     :: (IsLocated x, F.Symbolic x, F.Expression x, PP x) => x -> CGEnv -> CGM CGEnv
envRemSpec x g = do 
      ids <- F.lookupBindEnv x <$> binds <$> get 
      return $ g { cge_spec = E.envDel x $ cge_spec g 
                 , renv     = E.envDel x $ renv     g
                 , fenv     = foldr F.deleteIBindEnv (fenv g) ids }


-- | A global variable should have an entry in `cge_spec`.
---------------------------------------------------------------------------------------
isGlobalVar :: F.Symbolic x => x -> CGEnv -> Bool
---------------------------------------------------------------------------------------
isGlobalVar x g = E.envMem x $ cge_spec g
    

---------------------------------------------------------------------------------------
envToList     ::  CGEnv -> [(Id SourceSpan, RefType)]
---------------------------------------------------------------------------------------
envToList g = E.envToList $ renv g


---------------------------------------------------------------------------------------
envFindReturn :: CGEnv -> RefType 
---------------------------------------------------------------------------------------
envFindReturn = E.envFindReturn . renv


-- | Monad versions of TDefEnv operations
findSymOrDieM i = findSymOrDie i <$> getDef
findSymM i      = findSym i      <$> getDef



---------------------------------------------------------------------------------------
-- | Fresh Templates
---------------------------------------------------------------------------------------

-- | Instantiate Fresh Type (at Function-site)
---------------------------------------------------------------------------------------
freshTyFun :: (IsLocated l) => CGEnv -> l -> Id AnnTypeR -> RefType -> CGM RefType 
---------------------------------------------------------------------------------------
freshTyFun g l f t = freshTyFun' g l f t . kVarInst . cg_opts =<< get  

freshTyFun' g l _ t b
  | b && isTrivialRefType t = freshTy "freshTyFun" (toType t) >>= wellFormed l g
  | otherwise               = return t

freshTyVar g l t 
  | isTrivialRefType t      = freshTy "freshTyVar" (toType t) >>= wellFormed l g
  | otherwise               = return t

-- | Instantiate Fresh Type (at Call-site)
freshTyInst l g αs τs tbody
  = do ts    <- mapM (freshTy "freshTyInst") τs
       _     <- mapM (wellFormed l g) ts
       return $ apply (fromList $ zip αs ts) tbody

-- | Instantiate Fresh Type (at Phi-site) 
---------------------------------------------------------------------------------------
freshTyPhis :: (PP l, IsLocated l) => l -> CGEnv -> [Id l] -> [Type] -> CGM (CGEnv, [RefType])  
---------------------------------------------------------------------------------------
freshTyPhis l g xs τs 
  = do ts <- mapM    (freshTy "freshTyPhis")  τs
       g' <- envAdds (safeZip "freshTyPhis" xs ts) g
       _  <- mapM    (wellFormed l g') ts
       return (g', ts)

---------------------------------------------------------------------------------------
freshTyPhisWhile :: (PP l, IsLocated l) => l -> CGEnv -> [Id l] -> [Type] -> CGM (CGEnv, [RefType])  
---------------------------------------------------------------------------------------
freshTyPhisWhile l g xs τs 
  = do ts <- mapM    (freshTy "freshTyPhis")  τs
       g' <- envAdds (safeZip "freshTyPhis" xs ts) g
       _  <- mapM    (wellFormed l g) ts
       return (g', ts)

-- | Fresh Object Type
---------------------------------------------------------------------------------------
freshTyObj :: (IsLocated l) => l -> CGEnv -> RefType -> CGM RefType 
---------------------------------------------------------------------------------------
freshTyObj l g t = freshTy "freshTyArr" t >>= wellFormed l g 

---------------------------------------------------------------------------------------
-- | Adding Subtyping Constraints
---------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------
subType :: (IsLocated l) => l -> CGEnv -> RefType -> RefType -> CGM ()
---------------------------------------------------------------------------------------
subType l g t1 t2 =
  do t1'   <- addInvariant t1
     t2'   <- addInvariant t2
     g'    <- envAdds [(symbolId l x, t) | (x, Just t) <- rNms t1' ++ rNms t2' ] g
     modify $ \st -> st {cs = c g' (t1', t2') : (cs st)}
  where
    c g     = uncurry $ Sub g (ci l)
    rNms t  = (\n -> (n, n `E.envFindTy` renv g)) <$> names t
    names   = foldReft rr []
    rr r xs = F.syms r ++ xs


--------------------------------------------------------------------------------
-- | Adding Well-Formedness Constraints
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
wellFormed       :: (IsLocated l) => l -> CGEnv -> RefType -> CGM RefType  
--------------------------------------------------------------------------------
wellFormed l g t = do modify $ \st -> st { ws = (W g (ci l) t) : ws st }
                      return t


--------------------------------------------------------------------------------
-- | Generating Fresh Values 
--------------------------------------------------------------------------------

class Freshable a where
  fresh   :: CGM a
  true    :: a -> CGM a
  true    = return . id
  refresh :: a -> CGM a
  refresh = return . id

instance Freshable Integer where
  fresh = do modify $ \st -> st { count = 1 + (count st) }
             count <$> get 

instance Freshable F.Symbol where
  fresh = F.tempSymbol "nano" <$> fresh

instance Freshable String where
  fresh = F.symbolString <$> fresh

-- | Freshen up
freshTy :: RefTypable a => s -> a -> CGM RefType
freshTy _ τ = refresh $ rType τ

instance Freshable F.Refa where
  fresh = (`F.RKvar` mempty) <$> (F.intKvar <$> fresh)

instance Freshable [F.Refa] where
  fresh = single <$> fresh

instance Freshable F.Reft where
  fresh                  = errorstar "fresh Reft"
  true    (F.Reft (v,_)) = return $ F.Reft (v, []) 
  refresh (F.Reft (_,_)) = curry F.Reft <$> ({-tracePP "freshVV" <$> -}freshVV) <*> fresh
    where freshVV        = F.vv . Just  <$> fresh

instance Freshable F.SortedReft where
  fresh                  = errorstar "fresh Reft"
  true    (F.RR so r)    = F.RR so <$> true r 
  refresh (F.RR so r)    = F.RR so <$> refresh r

instance Freshable RefType where
  fresh   = errorstar "fresh RefType"
  refresh = refreshRefType
  true    = trueRefType 

trueRefType    :: RefType -> CGM RefType
trueRefType    = mapReftM true

refreshRefType :: RefType -> CGM RefType
refreshRefType = mapReftM refresh

--------------------------------------------------------------------------------
-- | Splitting Subtyping Constraints 
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
splitC :: SubC -> CGM [FixSubC]
--------------------------------------------------------------------------------

-- | Function types
splitC (Sub g i tf1@(TFun xt1s t1 _) tf2@(TFun xt2s t2 _))
  = do bcs       <- bsplitC g i tf1 tf2
       g'        <- envTyAdds i xt2s g 
       cs        <- concatMapM splitC $ safeZipWith "splitC1" (Sub g' i) t2s t1s' 
       cs'       <- splitC $ Sub g' i (F.subst su t1) t2      
       return     $ bcs ++ cs ++ cs'
    where 
       t2s        = b_type <$> xt2s
       t1s'       = F.subst su (b_type <$> xt1s)
       su         = F.mkSubst $ safeZipWith "splitC2" bSub xt1s xt2s
       bSub b1 b2 = (b_sym b1, F.eVar $ b_sym b2)

-- | TAlls
splitC (Sub g i (TAll α1 t1) (TAll α2 t2))
  | α1 == α2 
  = splitC $ Sub g i t1 t2
  | otherwise   
  = splitC $ Sub g i t1 t2' 
  where 
    θ   = fromList [(α2, tVar α1 :: RefType)]
    t2' = apply θ t2

-- | TVars
splitC (Sub g i t1@(TVar α1 _) t2@(TVar α2 _)) 
  | α1 == α2
  = bsplitC g i t1 t2
  | otherwise
  = errorstar "UNEXPECTED CRASH in splitC"

-- | Unions
-- FIXME: Uneven unions
splitC (Sub g i t1 t2)
  | any isUnion [t1, t2]
  = getDef >>= \δ -> match t1 (zipType δ (\p _ -> p) F.bot t2 t1)
    where 
      match t1@(TApp TUn t1s r1) t2@(TApp TUn t2s r2) = do
        cs      <- bsplitC g i t1 t2
        let t1s' = L.sortBy (compare `on` toType) $ (`strengthen` r1) <$> t1s
        let t2s' = L.sortBy (compare `on` toType) $ (`strengthen` r2) <$> t2s
        cs'     <- concatMapM splitC $ safeZipWith "splitC-Unions" (Sub g i) t1s' t2s'
        return   $ cs ++ cs'
      match t1' t2' = splitC (Sub g i t1' t2')

-- |Type references
splitC (Sub g i t1@(TApp (TRef i1) t1s _) t2@(TApp (TRef i2) t2s _)) 
  | i1 == i2
  = do  cs    <- bsplitC g i t1 t2
        -- FIXME: Variance !!!
        cs'   <- concatMapM splitC $ safeZipWith "splitC-TRef" (Sub g i) t1s t2s
                                  -- ++ safeZipWith "splitC-TRef" (Sub g i) t2s t1s
        return $ cs ++ cs' 
  | otherwise 
  = do  cs    <- bsplitC g i t1 t2
        e1s <- (`flattenTRef` t1) <$> getDef
        e2s <- (`flattenTRef` t2) <$> getDef
        cs' <- splitE g i (remCons e1s) (remCons e2s)
        return $ cs ++ cs'
    where
        remCons es = [ e | e <- es, not (isConstr e) ]

-- FIXME: Add constraint for null
splitC (Sub _ _ (TApp (TRef _) _ _) (TApp TNull _ _)) 
  = return []

splitC (Sub _ _ (TApp TNull _ _) (TApp (TRef _) _ _)) 
  = return []

splitC (Sub g i t1@(TApp (TRef _) _ _) t2@(TCons _ _))
  = do t1' <- (`flattenType` t1) <$> getDef
       splitC (Sub g i t1' t2)

splitC (Sub g i t1@(TCons _ _) t2@(TApp (TRef _) _ _))
  = do t2' <- (`flattenType` t2) <$> getDef
       splitC (Sub g i t1 t2')

splitC (Sub _ _ t1@(TApp (TRef _) _ _) t2)
  = errorstar $ "UNEXPECTED CRASH in splitC: " ++ ppshow t1 ++ " vs " ++ ppshow t2

splitC (Sub _ _ t1 t2@(TApp (TRef _) _ _))
  = errorstar $ "UNEXPECTED CRASH in splitC: " ++ ppshow t1 ++ " vs " ++ ppshow t2

-- | Rest of TApp
splitC (Sub g i t1@(TApp _ t1s _) t2@(TApp _ t2s _))
  = do cs    <- bsplitC g i t1 t2
       cs'   <- concatMapM splitC $ safeZipWith 
                                    (printf "splitC4: %s - %s" (ppshow t1) (ppshow t2)) 
                                    (Sub g i) t1s t2s
       return $ cs ++ cs'

-- | TCons
-- FIXME: Variance !!!
splitC (Sub g i t1@(TCons e1s _ ) t2@(TCons e2s _ ))
  -- LHS and RHS are object literal types
  | all (not . isIndSig) [t1,t2]  
  = do cs    <- bsplitC g i t1 t2
       when (length t1s /= length t2s) 
         $ error $ "splitC on non aligned TCons: " ++ ppshow t1 ++ "\n" ++ ppshow t2
       cs'   <- concatMapM splitC $ safeZipWith "splitC1" (Sub g i) t1s t2s -- CO-VARIANCE
       return $ cs ++ cs'

  -- LHS and RHS are index signatures
  | all isIndSig [t1,t2]          
  = do c1 <- bsplitC g i t1 t2
       c2 <- splitC $ Sub g i (ti e1s) (ti e2s)
       return $ c1 ++ c2

  -- One of the sides is an index signature
  | isIndSig t2 
  = do c1 <- bsplitC g i t1 t2
       c2 <- concatMapM splitC $ zipWith (Sub g i) (ts e1s) (repeat $ ti e2s)
       return $ c1 ++ c2

  | isIndSig t1
  = do c1 <- bsplitC g i t1 t2
       c2 <- concatMapM splitC $ zipWith (Sub g i) (repeat $ ti e1s) (ts e2s)
       return $ c1 ++ c2
  
  | otherwise 
  = error "BUG:splitC:TCons"

  where
    ts es = [ eltType e | e <- es, nonStaticElt e ]
    ti es = safeHead "convertCons" [ t | IndexSig _ _ t <- es ]
    t1s   = [ eltType e | e <- e1s, nonStaticElt e ]
    t2s   = [ eltType e | e <- e2s, nonStaticElt e ]
  
splitC x 
  = cgError l $ bugBadSubtypes l x where l = srcPos x


---------------------------------------------------------------------------------------
splitE :: CGEnv -> Cinfo -> [TElt RefType] -> [TElt RefType] -> CGM [FixSubC]
---------------------------------------------------------------------------------------
splitE g i e1s e2s
    | length e1s == length e2s 
    = concatMapM splitC $ zipWith (Sub g i) t1s t2s
    | otherwise
    = cgError l $ bugMalignedFields l e1s e2s 
  where
    l   = srcPos i
    t1s = f_type <$> L.sortBy (compare `on` f_sym) e1s  
    t2s = f_type <$> L.sortBy (compare `on` f_sym) e2s


---------------------------------------------------------------------------------------
bsplitC :: CGEnv -> a -> RefType -> RefType -> CGM [F.SubC a]
---------------------------------------------------------------------------------------
bsplitC g ci t1 t2 = bsplitC' g ci <$> addInvariant t1 <*> addInvariant t2

bsplitC' g ci t1 t2
  | F.isFunctionSortedReft r1 && F.isNonTrivialSortedReft r2
  = F.subC (fenv g) F.PTrue (r1 {F.sr_reft = fTop}) r2 Nothing [] ci
  | F.isNonTrivialSortedReft r2
  = F.subC (fenv g) p r1 r2 Nothing [] ci
  | otherwise
  = []
  where
    p  = F.pAnd $ guards g
    r1 = clear $ rTypeSortedReft t1
    r2 = clear $ rTypeSortedReft t2

instance PP (F.SortedReft) where
  pp (F.RR _ b) = pp b

---------------------------------------------------------------------------------------
-- | Splitting Well-Formedness Constraints
---------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------
splitW :: WfC -> CGM [FixWfC]
---------------------------------------------------------------------------------------
splitW (W g i ft@(TFun ts t _)) 
  = do let bws = bsplitW g ft i
       g'     <- envTyAdds i ts g 
       ws     <- concatMapM splitW [W g' i ti | B _ ti <- ts]
       ws'    <-            splitW (W g' i t)
       return  $ bws ++ ws ++ ws'

splitW (W g i (TAll _ t)) 
  = splitW (W g i t)

splitW (W g i t@(TVar _ _))
  = return $ bsplitW g t i 

splitW (W g i t@(TApp _ ts _))
  =  do let ws = bsplitW g t i
        ws'   <- concatMapM splitW [W g i ti | ti <- ts]
        return $ ws ++ ws'

splitW (W g i (TAnd ts))
  = concatMapM splitW [W g i t | t <- ts]

splitW (W g i t@(TCons es _))
  = do let bws = bsplitW g t i
       -- FIXME: add field bindings in g?
       ws     <- concatMapM splitW [ W g i $ eltType e | e <- es ]
       return  $ bws ++ ws

splitW (W _ _ t) = error $ render $ text "Not supported in splitW: " <+> pp t

bsplitW g t i 
  | F.isNonTrivialSortedReft r'
  = [F.wfC (fenv g) (clear r') Nothing i] 
  | otherwise
  = []
  where r' = rTypeSortedReft t

envTyAdds l xts = envAdds [(symbolId l x, t) | B x t <- xts]


---------------------------------------------------------------------------------------
-- | Replace all sorts with FInt


class ClearSorts a where
  clear :: a -> a

instance ClearSorts F.BindEnv where
  clear = F.mapBindEnv (mapSnd clear)

instance (ClearSorts a, ClearSorts b) => ClearSorts (a,b) where
  clear (a,b) = (clear a, clear b)

instance ClearSorts a => ClearSorts [a] where
  clear xs = clear <$> xs

instance ClearSorts F.SortedReft where
  clear (F.RR s r) = F.RR (clear s) r

instance ClearSorts F.Sort where 
  clear t@F.FInt        = F.FInt
  clear t@F.FNum        = F.FInt
  clear t@(F.FObj _)    = F.FInt
  clear t@(F.FVar _)    = F.FInt
  clear t@(F.FFunc i s) = F.FFunc i $ clear <$> s
  clear t@(F.FApp _ _ ) = F.FInt -- F.FApp  c $ clear s

instance ClearSorts F.Symbol where
  clear = id

instance ClearSorts F.Qualifier where
  clear (F.Q n p b)   = F.Q n (clear p) b 

instance ClearSorts (F.SEnv F.SortedReft) where
  clear = F.mapSEnvWithKey clearProp

clearProp (sy, F.RR so re) 
  | F.symbolString sy `elem` ["TRU", "FLS", "Prop"] 
  = (sy, F.RR so re)
  | otherwise                   
  = (clear sy, clear $ F.RR so re)

cgFunTys l f xs ft = 
  case funTys l f xs ft of 
    Left e  -> cgError l e 
    Right a -> return a



--------------------------------------------------------------------------------
-- | `this`

cgPeekThis = safeHead "get 'this'" <$> (cg_this <$> get)

cgPushThis t = modify $ \st -> st { cg_this = t : cg_this st } 

cgPopThis    = modify $ \st -> st { cg_this = tail $ cg_this st } 

cgWithThis t p = do { cgPushThis t; a <- p; cgPopThis; return a } 


--------------------------------------------------------------------------------
getSuperM :: IsLocated a => a -> RefType -> CGM RefType
--------------------------------------------------------------------------------
getSuperM l (TApp (TRef (i,s)) ts _) = fromTdef =<< findSymOrDieM i
  where fromTdef (TD _ _ vs (Just (p,ps)) _) = do
          return  $ apply (fromList $ zip vs ts) 
                  $ TApp (TRef (F.symbol p,s)) ps fTop
        fromTdef (TD _ _ _ Nothing _) = cgError l $ errorSuper (srcPos l) 
getSuperM l _  = cgError l $ errorSuper (srcPos l) 

--------------------------------------------------------------------------------
getSuperDefM :: IsLocated a => a -> RefType -> CGM (TDef RefType)
--------------------------------------------------------------------------------
getSuperDefM l (TApp (TRef (i,_)) ts _) = fromTdef =<< findSymOrDieM i
  where 
    fromTdef (TD _ _ vs (Just (p,ps)) _) = 
      do TD c n ws pp ee <- findSymOrDieM p
         return  $ apply (fromList $ zip vs ts) 
                 $ apply (fromList $ zip ws ps)
                 $ TD c n [] pp ee
    fromTdef (TD _ _ _ Nothing _) = cgError l $ errorSuper (srcPos l) 
getSuperDefM l _  = cgError l $ errorSuper (srcPos l)

