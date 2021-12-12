{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE StrictData #-}

module Katip.Wai (
  Request (..),
  ApplicationT,
  middleware,
  runApplication,
) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson ((.=))
import qualified Data.Aeson as Aeson
import Data.ByteString (ByteString)
import Data.Text (Text)
import Data.Text.Encoding (decodeUtf8With)
import Data.Text.Encoding.Error (lenientDecode)
import Data.UUID (UUID)
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUID.V4
import qualified Katip
import Network.HTTP.Types.URI (Query, queryToQueryText)
import Network.HTTP.Types.Version (HttpVersion)
import Network.Socket (SockAddr)
import qualified Network.Wai as Wai

data Request = Request
  { requestId :: UUID
  , requestHttpVersion :: HttpVersion
  , requestRemoteHost :: SockAddr
  , requestIsSecure :: Bool
  , requestPathInfo :: [Text]
  , requestQueryString :: Query
  , requestBodyLength :: Wai.RequestBodyLength
  , requestHeaderHost :: Maybe ByteString
  , requestHeaderReferer :: Maybe ByteString
  , requestHeaderUserAgent :: Maybe ByteString
  , requestHeaderRange :: Maybe ByteString
  }

toKeyValues :: Aeson.KeyValue kv => Request -> [kv]
toKeyValues Request{..} =
  let headers =
        let toText = fmap (decodeUtf8With lenientDecode)
         in Aeson.object
              [ "host" .= toText requestHeaderHost
              , "referer" .= toText requestHeaderReferer
              , "userAgent" .= toText requestHeaderUserAgent
              , "range" .= toText requestHeaderRange
              ]
   in [ "id" .= UUID.toText requestId
      , "httpVersion" .= show requestHttpVersion
      , "remoteHost" .= show requestRemoteHost
      , "isSecure" .= requestIsSecure
      , "path" .= requestPathInfo
      , "queryString" .= queryToQueryText requestQueryString
      , "bodyLength" .= show requestBodyLength
      , "headers" .= headers
      ]

instance Aeson.ToJSON Request where
  toJSON = Aeson.object . toKeyValues
  toEncoding = Aeson.pairs . mconcat . toKeyValues

toLoggableRequest :: Wai.Request -> IO Request
toLoggableRequest request = do
  requestId <- UUID.V4.nextRandom
  pure
    Request
      { requestId = requestId
      , requestHttpVersion = Wai.httpVersion request
      , requestRemoteHost = Wai.remoteHost request
      , requestIsSecure = Wai.isSecure request
      , requestPathInfo = Wai.pathInfo request
      , requestQueryString = Wai.queryString request
      , requestBodyLength = Wai.requestBodyLength request
      , requestHeaderHost = Wai.requestHeaderHost request
      , requestHeaderReferer = Wai.requestHeaderReferer request
      , requestHeaderUserAgent = Wai.requestHeaderUserAgent request
      , requestHeaderRange = Wai.requestHeaderRange request
      }

type ApplicationT m = Wai.Request -> (Wai.Response -> m Wai.ResponseReceived) -> m Wai.ResponseReceived

middleware :: Katip.KatipContext m => ApplicationT m -> ApplicationT m
middleware application request send = do
  loggableRequest <- liftIO $ toLoggableRequest request
  Katip.katipAddContext (Katip.sl "request" loggableRequest) $
    application request send

runApplication :: MonadIO m => (forall a. m a -> IO a) -> ApplicationT m -> Wai.Application
runApplication toIO application request send =
  toIO $ application request (liftIO . send)
