module Discord
  struct StageInstance
    include JSON::Serializable

    property id : Snowflake
    property guild_id : Snowflake
    property channel_id : Snowflake
    property topic : String
    @[JSON::Field(converter: Enum::ValueConverter(Discord::PrivacyLevel))]
    property privacy_level : PrivacyLevel
    property discoverable_disabled : Bool
  end

  enum PrivacyLevel
    Public    = 1
    GuildOnly = 2
  end
end
