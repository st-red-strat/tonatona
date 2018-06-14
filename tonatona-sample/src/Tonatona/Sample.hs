{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

module Tonatona.Sample
  where

import Control.Monad.IO.Class (liftIO)
import Data.Aeson
import Data.Semigroup ((<>))
import Data.Text (Text)
import Data.Void
import Database.Persist.Postgresql
import Database.Persist.TH
import System.Envy (FromEnv(..))
import Servant
import Tonatona (Plug(..), TonaM, lift)
import qualified Tonatona as Tona
import qualified Tonatona.IO as TonaIO
import Tonatona.Db.Sql (TonaDbConfig, TonaDbSqlShared, runPostgres)
import qualified Tonatona.Db.Sql as TonaDb
import Tonatona.Environment (TonaEnvConfig(..))
import qualified Tonatona.Environment as TonaEnv
import Tonatona.Logger (TonaLoggerShared(..), logDebug, logInfo, stdoutLogger)
import qualified Tonatona.Logger as TonaLogger
import qualified Tonatona.Servant as TonaServant
import Tonatona.Servant (TonaServantConfig(..))


$(share
  [ mkPersist sqlSettings {mpsGenerateLenses = False}
  , mkMigrate "migrateAll"
  ]
  [persistLowerCase|
  Tag
    name      Text
    value      Text

    deriving Eq
    deriving Show
    |]
 )

type TagAPI = "tag" :> (
  Capture "tagname" Text :> Capture "tagvalue" Text :> Post '[JSON] () :<|>
    Capture "tagname" Text :> Get '[JSON] [Text]
  )

type API =
  "foo" :> Get '[JSON] Int :<|>
  TagAPI :<|>
  "redirect-example" :> Get '[JSON] Void

server :: ServerT API (TonaM Config Shared)
server = getFoo :<|> tagServer :<|> redirectExample

getFoo :: TonaM Config Shared Int
getFoo = do
  $(logInfo) "in getFoo, returning 1"
  pure 1

tagServer :: ServerT TagAPI (TonaM Config Shared)
tagServer = postTag :<|> getTag

postTag :: Text -> Text -> TonaM Config Shared ()
postTag name val = do
  TonaDb.run $ do
    $(logInfo) $
      "in postTag, in TonaDb.run, inserting a tag with name = " <>
      name <> ", val = " <> val
    insert_ (Tag name val)

getTag :: Text -> TonaM Config Shared [Text]
getTag name = do
  tagEnts <- TonaDb.run $
    selectList [TagName ==. name] []
  pure $ tagValue . entityVal <$> tagEnts

redirectExample :: TonaM Config Shared Void
redirectExample = TonaServant.redirect "https://google.com"

instance ToJSON Void where toJSON = absurd

app :: IO ()
app =
  Tona.run $ do
    $(logDebug) "About to run migration..."
    TonaDb.runMigrate migrateAll
    $(logDebug) "About to run web server..."
    TonaServant.run @API server

-- Config

data Config = Config
  { tonaDb :: TonaDb.Config
  , tonaEnv :: TonaEnv.Config
  , tonaServant :: TonaServant.Config
  }
  deriving (Show)

instance FromEnv Config where
  fromEnv = Config
    <$> fromEnv
    <*> fromEnv
    <*> fromEnv

instance TonaDbConfig Config where
  config = tonaDb

instance TonaEnvConfig Config where
  config = tonaEnv

instance TonaServantConfig Config where
  config = tonaServant


-- Shared

data Shared = Shared
  { tonaDb :: TonaDb.Shared
  , tonaLogger :: TonaLogger.Shared
  }

instance Plug Config Shared where
  init conf = Shared
    <$> TonaDb.init conf stdoutLogger runPostgres
    <*> TonaLogger.init stdoutLogger

instance TonaDbSqlShared Shared where
  shared = tonaDb

instance TonaLoggerShared Shared where
  shared = tonaLogger
