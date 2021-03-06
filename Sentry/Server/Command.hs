{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
-- |
-- Module      : Sentry.Server.Command
-- Copyright   : (c) 2012 Vo Minh Thu,
--
-- License     : BSD-style
-- Maintainer  : thu@hypered.be
-- Stability   : experimental
-- Portability : GHC
--
-- This module provides the command-line interface for a Sentry program. It
-- defines data types to represent different subcommands and the corresponding
-- functions.
module Sentry.Server.Command where

import Control.Concurrent (forkIO)
import Control.Concurrent.Chan (newChan)
import Control.Concurrent.MVar

import System.Console.CmdArgs.Implicit

import Sentry.Server.Core
import Sentry.Server.Http (serve)
import Sentry.Server.Types (Entry(..))

-- | 'sentry' provides the main function of a Sentry configuration file. In
-- particular it provides the command-line interface. It takes a list of
-- configuration entries as its sole argument.
sentry :: [Entry] -> IO ()
sentry entries = (runCmd =<<) $ cmdArgs $
  modes
    [ cmdStart entries
    , cmdContinue entries
    , cmdCompile
    , cmdReload
    ]
  &= summary versionString
  &= program "sentryd"

-- | String with the program name, version and copyright.
versionString :: String
versionString =
  "Sentry Server - Process monitoring. Copyright (c) 2012 Vo Minh Thu."
  -- TODO add the version.

-- | Data type representing the different command-line subcommands.
data Cmd =
    Start { cmdEntries :: [Entry] }
    -- ^ Start Sentry with the provided process specifications.
  | Continue { cmdEntries :: [Entry] }
    -- ^ Resume Sentry with the provided process specifications.
  | Compile
    -- ^ Compile Sentry.
  | Reload
    -- ^ Reload Sentry.
  deriving (Data, Typeable)

-- | Create a 'Start' command.
cmdStart :: [Entry] -> Cmd
cmdStart entries = Start
  { cmdEntries = entries
    &= ignore
  } &= help "Start Sentry."
    &= explicit
    &= name "start"

-- | Create a 'Continue' command.
cmdContinue :: [Entry] -> Cmd
cmdContinue entries = Continue
  { cmdEntries = entries
    &= ignore
  } &= help ("Resume Sentry after a graceful exit or SIGHUP." ++
      " This is normally not called explicitely from the command-line.")
    &= explicit
    &= name "continue"

-- | Create a 'Compile' command.
cmdCompile :: Cmd
cmdCompile = Compile
  &= help "Compile the configuration file, replacing this executable."
  &= explicit
  &= name "compile"

-- | Create a 'Reload' command.
cmdReload :: Cmd
cmdReload = Reload
  &= help "Instruct a running Sentry to reload itself by sending it a SIGHUP."
  &= explicit
  &= name "reload"

-- | Run a Sentryd sub-command.
runCmd :: Cmd -> IO ()
runCmd Start{..} = do
  state <- initializeState cmdEntries
  chan <- newChan
  stateVar <- newMVar state
  _ <- forkIO $ serve stateVar chan
  startMonitor state stateVar chan

runCmd Continue{..} = do
  mstate <- readState
  case mstate of
    Nothing -> return ()
    Just state -> do
      chan <- newChan
      stateVar <- newMVar state
      _ <- forkIO $ serve stateVar chan
      continueMonitor state cmdEntries stateVar chan

runCmd Compile{..} = do
  state <- initializeState []
  _ <- compile state
  return ()

runCmd Reload{..} = do
  state <- initializeState []
  sendSIGHUP state
