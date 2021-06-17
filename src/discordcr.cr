require "log"
require "http/client"
require "http/formdata"
require "openssl/ssl/context"
require "time/format"
require "json"
require "uri"
require "./discordcr/mappings/*"
require "./discordcr/*"

module Discord
  Log = ::Log.for("discord")
end
