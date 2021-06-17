module Discord
  struct Webhook
    include JSON::Serializable

    property id : Snowflake
    @[JSON::Field(converter: Enum::ValueConverter(Discord::WebhookType))]
    property type : WebhookType
    property guild_id : Snowflake?
    property channel_id : Snowflake?
    property user : User?
    property name : String?
    property avatar : String?
    property token : String?
    property application_id : Snowflake?
    property source_guild : WebhookGuild?
    property source_channel : WebhookChannel?
    property url : String?
  end

  enum WebhookType
    Incoming        = 1
    ChannelFollower = 2
    Application     = 3
  end

  struct WebhookGuild
    include JSON::Serializable

    property id : Snowflake
    property name : String
    property icon : String?
  end

  struct WebhookChannel
    include JSON::Serializable

    property id : Snowflake
    property name : String
  end
end
