module Discord
  struct GuildTemplate
    include JSON::Serializable

    property code : String
    property name : String
    property description : String?
    property usage_count : UInt32
    property creator_id : Snowflake
    property creator : User
    @[JSON::Field(converter: Discord::TimestampConverter)]
    property created_at : Time
    @[JSON::Field(converter: Discord::TimestampConverter)]
    property updated_at : Time
    property source_guild_id : Snowflake
    property serialized_source_guild : SourceGuild
    property is_dirty : Bool?
  end

  struct SourceGuild
    include JSON::Serializable

    property name : String
    property description : String?
    property region : String
    @[JSON::Field(converter: Enum::ValueConverter(Discord::VerificationLevel))]
    property verification_level : VerificationLevel
    @[JSON::Field(converter: Enum::ValueConverter(Discord::MessageNotificationLevel))]
    property default_message_notifications : MessageNotificationLevel
    @[JSON::Field(converter: Enum::ValueConverter(Discord::ExplicitContentFilter))]
    property explicit_content_filter : ExplicitContentFilter
    property preferred_locale : String
    property afk_timeout : Int32?
    property roles : Array(RoleTemplate)
    property channels : Array(ChannelTemplate)
    property afk_channel_id : UInt32?
    property system_channel_id : UInt32?
    @[JSON::Field(converter: Enum::ValueConverter(Discord::SystemChannelFlags))]
    property system_channel_flags : SystemChannelFlags
    property icon_hash : String?
  end

  struct RoleTemplate
    include JSON::Serializable

    property id : UInt32
    property name : String
    @[JSON::Field(key: "color")]
    property colour : UInt32
    property hoist : Bool
    property permissions : Permissions
    property mentionable : Bool
    property tags : RoleTags?

    {% unless flag?(:correct_english) %}
      def color
        colour
      end
    {% end %}
  end

  struct ChannelTemplate
    include JSON::Serializable

    property id : UInt32
    @[JSON::Field(converter: Enum::ValueConverter(Discord::ChannelType))]
    property type : ChannelType
    property guild_id : Snowflake?
    property position : Int32?
    property permission_overwrites : Array(OverwriteTemplate)?
    property name : String?
    property topic : String?
    property nsfw : Bool?
    property bitrate : UInt32?
    property user_limit : UInt32?
    property rate_limit_per_user : UInt32?
    property recipients : Array(User)?
    property icon : String?
    property parent_id : UInt32?
    property rtc_region : String?
    @[JSON::Field(converter: Enum::ValueConverter(Discord::VideoQualityMode))]
    property video_quality_mode : VideoQualityMode?
  end

  struct OverwriteTemplate
    include JSON::Serializable

    property id : UInt32
    @[JSON::Field(converter: Enum::ValueConverter(Discord::OverwriteType))]
    property type : OverwriteType
    property allow : Permissions
    property deny : Permissions
  end
end
