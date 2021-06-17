module Discord
  struct VoiceState
    include JSON::Serializable

    property guild_id : Snowflake?
    property channel_id : Snowflake?
    property user_id : Snowflake
    property member : GuildMember?
    property session_id : String
    property deaf : Bool
    property mute : Bool
    property self_deaf : Bool
    property self_mute : Bool
    property self_stream : Bool?
    property self_video : Bool
    property suppress : Bool
    @[JSON::Field(converter: Discord::MaybeTimestampConverter)]
    property request_to_speak_timestamp : Time?
  end

  struct VoiceRegion
    include JSON::Serializable

    property id : String
    property name : String
    property vip : Bool
    property optimal : Bool
    property deprecated : Bool
    property custom : Bool
  end
end
