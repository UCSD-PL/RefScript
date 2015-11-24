{-# LANGUAGE ScopedTypeVariables #-}

-- | This module contains Haskell variables representing globally visible
-- names for files, paths, extensions.


module Language.Rsc.Core.Files (
  -- * Hardwired paths
    getPreludeJSONPath
  , getPreludeTSPath
  , getDomJSONPath
  , getDomTSPath
  , getTSBindPath
  )
  where

import           Control.Applicative
import           System.FilePath

import           Paths_refscript


-------------------------------------------------------------------------------
getPreludeTSPath, getDomTSPath, getPreludeJSONPath, getDomJSONPath :: IO FilePath
-------------------------------------------------------------------------------
getPreludeTSPath   = getDataFileName "include/prelude.d.ts"
getDomTSPath       = getDataFileName "include/ambient/dom.ts"
getPreludeJSONPath = (`replaceExtension` ".json") <$> getPreludeTSPath
getDomJSONPath     = (`replaceExtension` ".json") <$> getDomTSPath

getTSBindPath      = getDataFileName "./ext/tsc-bin/built/local/tsc-refscript.js"



getPrimsTSPath     = getDataFileName "include/rsc/prims.ts"
getPrimsJSONPath   = (`replaceExtension` ".json") <$> getPrimsTSPath
