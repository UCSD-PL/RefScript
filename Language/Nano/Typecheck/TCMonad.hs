{- LANGUAGE TypeSynonymInstances #-}
{- LANGUAGE FlexibleInstances    #-}
{- LANGUAGE NoMonomorphismRestriction #-}
{- LANGUAGE ScopedTypeVariables  #-}

-- | This module has the code for the Type-Checker Monad. 
--   You /need not/ modify the code here, just use the exported API.

module Language.Nano.Typecheck.TCMonad (
  -- * TC Monad
    TCM
 
  -- * Execute 
  , execute

  -- * Log Errors
  , logError
  
  -- * Error Action
  , tcError

  -- * Freshness
  , freshTyArgs

  -- * Substitutions
  , getSubst, setSubst

  -- * Annotations
  , accumAnn
  , getAllAnns

  -- * Unification
  , unifyType
  , unifyTypes

  -- * Subtyping
  , subTypes
  , subType

  -- * Get Type Signature 
  , getDefType 
  )  where 

import           Text.Printf
import           Control.Applicative          ((<$>))
import           Control.Monad.State
import           Control.Monad.Error
import           Language.Fixpoint.Misc 
import qualified Language.Fixpoint.Types as F

import           Language.Nano.Env
import           Language.Nano.Types
import           Language.Nano.Typecheck.Types
import           Language.Nano.Typecheck.Subst
import           Language.Nano.Errors
import           Data.Monoid                  
import qualified Data.HashSet as S
import qualified Data.HashMap.Strict     as M
import           Data.List           (partition)
import           Text.Parsec.Pos              
import           Language.ECMAScript3.Parser        (SourceSpan (..))

-------------------------------------------------------------------------------
-- | Typechecking monad -------------------------------------------------------
-------------------------------------------------------------------------------

data TCState = TCS { tc_errss :: ![(SourceSpan, String)]
                   , tc_errs  :: ![String]
                   , tc_subst :: !Subst
                   , tc_cnt   :: !Int
                   , tc_anns  :: AnnInfo
                   , tc_annss :: [AnnInfo]
                   , tc_defs  :: !(Env Type) 
                   }

type TCM     = ErrorT String (State TCState)

-------------------------------------------------------------------------------
getSubst :: TCM Subst
-------------------------------------------------------------------------------
getSubst = tc_subst <$> get 

-------------------------------------------------------------------------------
setSubst   :: Subst -> TCM () 
-------------------------------------------------------------------------------
setSubst θ = modify $ \st -> st { tc_subst = θ }

-------------------------------------------------------------------------------
extSubst :: [TVar] -> TCM ()
-------------------------------------------------------------------------------
extSubst βs = getSubst >>= setSubst . (`mappend` θ')
  where 
    θ'      = fromList $ zip βs (tVar <$> βs)


-------------------------------------------------------------------------------
tcError :: (IsLocated l) => l -> String -> TCM a
-------------------------------------------------------------------------------
tcError l msg = throwError $ printf "TC-ERROR at %s : %s" (ppshow $ srcPos l) msg


-------------------------------------------------------------------------------
logError   :: SourceSpan -> String -> a -> TCM a
-------------------------------------------------------------------------------
logError l msg x = (modify $ \st -> st { tc_errss = (l,msg):(tc_errss st)}) >> return x


-------------------------------------------------------------------------------
freshTyArgs :: SourceSpan -> ([TVar], Type) -> TCM Type 
-------------------------------------------------------------------------------
freshTyArgs l (αs, t) 
  = (`apply` t) <$> freshSubst l αs

freshSubst :: SourceSpan -> [TVar] -> TCM Subst
freshSubst l αs
  = do βs <- mapM (freshTVar l) αs
       setTyArgs l βs
       extSubst βs 
       return $ fromList $ zip αs (tVar <$> βs)

setTyArgs l βs 
  = do m <- tc_anns <$> get 
       when (M.member l m) $ tcError l "Multiple Type Args"
       addAnn l $ TypInst (tVar <$> βs)



-------------------------------------------------------------------------------
-- | Managing Annotations: Type Instantiations --------------------------------
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
getAnns :: TCM AnnInfo  
-------------------------------------------------------------------------------
getAnns = do θ     <- tc_subst <$> get
             m     <- tc_anns  <$> get
             let m' = fmap (apply θ . sortNub) m
             _     <- modify $ \st -> st { tc_anns = m' }
             return m' 

-------------------------------------------------------------------------------
addAnn :: SourceSpan -> Fact -> TCM () 
-------------------------------------------------------------------------------
addAnn l f = modify $ \st -> st { tc_anns = inserts l f (tc_anns st) } 

-------------------------------------------------------------------------------
getAllAnns :: TCM [AnnInfo]  
-------------------------------------------------------------------------------
getAllAnns = tc_annss <$> get


-------------------------------------------------------------------------------
accumAnn :: (AnnInfo -> [(SourceSpan, String)]) -> TCM () -> TCM ()
-------------------------------------------------------------------------------
accumAnn check act 
  = do m     <- tc_anns <$> get 
       modify $ \st -> st {tc_anns = M.empty}
       act
       m'    <- getAnns
       forM_ (check m') $ \(l, s) -> logError l s ()
       modify $ \st -> st {tc_anns = m} {tc_annss = m' : tc_annss st}

-------------------------------------------------------------------------------
execute     :: Nano z (RType r) -> TCM a -> Either [(SourceSpan, String)] a
-------------------------------------------------------------------------------
execute pgm act 
  = case runState (runErrorT act) $ initState pgm of 
      (Left err, _) -> Left [(dummySpan,  err)]
      (Right x, st) ->  applyNonNull (Right x) Left (reverse $ tc_errss st)

initState :: Nano z (RType r) -> TCState
initState pgm = TCS [] [] mempty 0 M.empty [] (envMap toType $ defs pgm) 


getDefType f 
  = do m <- tc_defs <$> get
       maybe err return $ envFindTy f m 
    where 
       err = tcError l $ errorMissingSpec l f
       l   = srcPos f


-------------------------------------------------------------------------------
accumErrs :: AnnSSA -> TCM ()
-------------------------------------------------------------------------------
accumErrs l
  = do m     <- tc_errs <$> get 
       modify   $ \st -> st {tc_errs = []}
       forM_  m $ \s -> logError (ann l) s ()


--------------------------------------------------------------------------
-- | Generating Fresh Values ---------------------------------------------
--------------------------------------------------------------------------

tick :: TCM Int
tick = do st    <- get 
          let n  = tc_cnt st
          put    $ st { tc_cnt = n + 1 }
          return n 

class Freshable a where 
  fresh :: a -> TCM a 

-- instance Freshable TVar where 
--   fresh _ = TV . F.intSymbol "T" <$> tick

instance Freshable a => Freshable [a] where 
  fresh = mapM fresh

freshTVar l _ =  ((`TV` l). F.intSymbol "T") <$> tick
              

----------------------------------------------------------------------------------
unifyTypes :: AnnSSA -> String -> [Type] -> [Type] -> TCM Subst
----------------------------------------------------------------------------------
unifyTypes l msg t1s t2s
  | length t1s /= length t2s = getSubst >>= logError (ann l) errorArgMismatch
  | otherwise                = do θ  <- getSubst 
                                  θ' <- unifys θ t1s t2s
                                  {-addError msg-}
                                  accumErrs l
                                  setSubst θ' 
                                  return θ'
                                  {- Left msg' -> logError (ann l) (msg ++ "\n" ++ msg') θ-}
                                  {- Right θ'  -> setSubst θ' >> return θ' -}

unifyType l m e t t' = unifyTypes l msg [t] [t'] >> return ()
  where 
    msg              = errorWrongType m e t t'


----------------------------------------------------------------------------------
subTypes :: AnnSSA -> [Type] -> [Type] -> TCM Subst
----------------------------------------------------------------------------------
subTypes l t1s t2s
  | length t1s /= length t2s = getSubst >>= logError (ann l) errorArgMismatch 
  | otherwise                = do θ  <- getSubst
                                  θ' <- subtys θ t1s t2s
                                  accumErrs l
                                  setSubst θ' 
                                  return θ'

subType l _ t t' = subTypes l [t] [t'] >> return ()
  {-where -}
  {-  msg              = errorSubType "subType" t t'-}


-----------------------------------------------------------------------------
unify :: Subst -> Type -> Type -> TCM Subst
-----------------------------------------------------------------------------
unify θ (TFun xts t _) (TFun xts' t' _) = unifys θ (t: (b_type <$> xts)) (t': (b_type <$> xts'))
unify θ (TVar α _) (TVar β _)           = varEql θ α β 
unify θ (TVar α _) t                    = varAsnM θ α t 
unify θ t (TVar α _)                    = varAsnM θ α t

unify θ (TApp c ts _) (TApp c' ts' _)
  | c == c'                             = unifys  θ ts ts'

unify θ t t' 
  | t == t'                             = return θ
  | isTop t                             = go θ $ strip t'
  | isTop t'                            = go θ $ strip t
  | otherwise                           = addError (errorUnification t t') θ
  where strip (TApp _ xs _ )            = xs
        strip x@(TVar _ _)              = [x]
        strip (TFun xs y _)             = (b_type <$> xs) ++ [y]
        strip (TAll _ x)                = [x]
        tops = map $ const tTop
        go θ ts = unifys θ ts $ tops ts



unifys         ::  Subst -> [Type] -> [Type] -> TCM Subst
unifys θ xs ys =  {- tracePP msg $ -} unifys' θ xs ys 
   where 
     msg      = printf "unifys: [xs = %s] [ys = %s]"  (ppshow xs) (ppshow ys)

unifys' θ ts ts' 
  | nTs == nTs' = go θ (ts, ts') 
  | otherwise   = addError (errorUnification ts ts') θ
  where 
    nTs                  = length ts
    nTs'                 = length ts'
    go θ (t:ts , t':ts') = unify θ t t' >>= \θ' -> go θ' (mapPair (apply θ') (ts, ts'))
    go θ (_    , _    )  = return θ 


-----------------------------------------------------------------------------
varEql :: Subst -> TVar -> TVar -> TCM Subst
-----------------------------------------------------------------------------
varEql θ α β = case varAsn θ α (tVar β) of 
                 Right θ' -> return θ'
                 Left e1  -> case varAsn θ β (tVar α) of
                                  Right θ' -> return θ'
                                  Left e2  -> addError (e1 ++ "\n OR \n" ++ e2) θ
 
-----------------------------------------------------------------------------
varAsn :: Subst -> TVar -> Type -> Either String Subst
-----------------------------------------------------------------------------
varAsn θ α t 
  | t == tVar α         = Right $ θ 
  | α `S.member` free t = Left  $ errorOccursCheck α t 
  | unassigned α θ      = Right $ θ `mappend` (Su $ M.singleton α t) 
  | otherwise           = Left  $ errorRigidUnify α t
  
unassigned α (Su m) = M.lookup α m == Just (tVar α)

-----------------------------------------------------------------------------
varAsnM :: Subst -> TVar -> Type -> TCM Subst
-----------------------------------------------------------------------------
varAsnM θ a t = 
  case varAsn θ a t of 
    Left s -> addError s θ
    Right θ' -> return θ


-----------------------------------------------------------------------------
subty :: Subst -> Type -> Type -> TCM Subst
-----------------------------------------------------------------------------
subty θ t t' | isTop t'      = unify θ t tTop

subty θ t@(TApp TUn ts _ ) t'@(TApp TUn ts' _) 
  | noTVars && subset ts ts' = return θ 
--  | noTVars && subset ts' ts = mkAnnot ts ts' 
  | noTVars                  = addError (errorSubType "Unions" t t') θ
  where 
    noTVars = not $ any var ts

subty θ t@(TApp TUn xs  _) t' = 
  case tvs of
    [ ]  | subset xs [t'] -> return θ       -- If it is a subset -- OK 
         | otherwise      -> unify θ t t'   -- Otherwise try to unify
    [v]                   -> unify θ v t' >>= if subset ts [t'] 
                                                then addError "subty"
                                                else return
    _                     -> addError (errorSubType "In subty" t t') θ
  where 
    (tvs, ts) = partition var xs

subty θ t t'@(TApp TUn ts _ ) 
  | subset [t] ts = return θ
  | otherwise     = unify θ t t'

subty θ t t' = unify θ t t'

var (TVar _ _) = True
var _          = False

-----------------------------------------------------------------------------
subtys ::  Subst -> [Type] -> [Type] -> TCM Subst
-----------------------------------------------------------------------------
subtys θ xs ys =  {- tracePP msg $ -} subtys' θ xs ys 
   where 
     msg      = printf "subtys: [xs = %s] [ys = %s]"  (ppshow xs) (ppshow ys)

subtys' θ ts ts' 
  | nTs == nTs' = go θ (ts, ts')
  | otherwise   = addError (errorSubType "" ts ts) θ
  where 
    nTs                  = length ts
    nTs'                 = length ts'
    go θ (t:ts , t':ts') = subty θ t t' >>= \θ' -> go θ' (mapPair (apply θ') (ts, ts'))
    go θ (_    , _    )  = return θ 


-------------------------------------------------------------------------------
addError   :: String -> a -> TCM a
-------------------------------------------------------------------------------
addError msg x = (modify $ \st -> st { tc_errs = msg:(tc_errs st)}) >> return x

