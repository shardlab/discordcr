require "./converters"
require "./voice"

module Discord
  struct Guild
    include JSON::Serializable

    property id : Snowflake
    property name : String
    property icon : String?
    property splash : String?
    property owner_id : Snowflake
    property region : String
    property afk_channel_id : Snowflake?
    property afk_timeout : Int32?
    # Removed in v8
    # property embed_enabled : Bool?
    # property embed_channel_id : Snowflake?
    property verification_level : UInt8
    property premium_tier : UInt8
    property premium_subscription_count : UInt8?
    property roles : Array(Role)
    @[JSON::Field(key: "emojis")]
    property emoji : Array(Emoji)
    property features : Array(String)
    property widget_enabled : Bool?
    property widget_channel_id : Snowflake?
    property default_message_notifications : UInt8
    property explicit_content_filter : UInt8
    property system_channel_id : Snowflake?
    property guild_scheduled_events : Array(GuildScheduledEvent)?

    # :nodoc:
    def initialize(payload : Gateway::GuildCreatePayload)
      @id = payload.id
      @name = payload.name
      @icon = payload.icon
      @splash = payload.splash
      @owner_id = payload.owner_id
      @region = payload.region
      @afk_channel_id = payload.afk_channel_id
      @afk_timeout = payload.afk_timeout
      @verification_level = payload.verification_level
      @premium_tier = payload.premium_tier
      @roles = payload.roles
      @emoji = payload.emoji
      @features = payload.features
      @widget_channel_id = payload.widget_channel_id
      @default_message_notifications = payload.default_message_notifications
      @explicit_content_filter = payload.explicit_content_filter
      @system_channel_id = payload.system_channel_id
      @guild_scheduled_events = payload.guild_scheduled_events
    end

    {% unless flag?(:correct_english) %}
      def emojis
        emoji
      end
    {% end %}

    # Produces a CDN URL to this guild's icon in the given `format` and `size`,
    # or `nil` if no icon is set.
    def icon_url(format : CDN::GuildIconFormat = CDN::GuildIconFormat::WebP,
                 size : Int32 = 128)
      if icon = @icon
        CDN.guild_icon(id, icon, format, size)
      end
    end

    # Produces a CDN URL to this guild's splash in the given `format` and `size`,
    # or `nil` if no splash is set.
    def splash_url(format : CDN::GuildSplashFormat = CDN::GuildSplashFormat::WebP,
                   size : Int32 = 128)
      if splash = @splash
        CDN.guild_splash(id, splash, format, size)
      end
    end
  end

  struct UnavailableGuild
    include JSON::Serializable

    property id : Snowflake
    property unavailable : Bool
  end

  struct GuildEmbed
    include JSON::Serializable

    property enabled : Bool
    property channel_id : Snowflake?
  end

  struct GuildMember
    include JSON::Serializable

    property user : User
    property nick : String?
    property roles : Array(Snowflake)?
    @[JSON::Field(converter: Discord::MaybeTimestampConverter)]
    property joined_at : Time?
    @[JSON::Field(converter: Discord::MaybeTimestampConverter)]
    property premium_since : Time?
    property deaf : Bool?
    property mute : Bool?
    property communication_disabled_until : Time?

    # :nodoc:
    def initialize(user : User, partial_member : PartialGuildMember)
      @user = user
      @roles = partial_member.roles
      @nick = partial_member.nick
      @joined_at = partial_member.joined_at
      @premium_since = partial_member.premium_since
      @mute = partial_member.mute
      @deaf = partial_member.deaf
      @communication_disabled_until = partial_member.communication_disabled_until
    end

    # :nodoc:
    def initialize(payload : Gateway::GuildMemberAddPayload | GuildMember, roles : Array(Snowflake), nick : String?)
      initialize(payload)
      @nick = nick
      @roles = roles
    end

    # :nodoc:
    def initialize(payload : Gateway::GuildMemberAddPayload | GuildMember)
      @user = payload.user
      @nick = payload.nick
      @roles = payload.roles
      @joined_at = payload.joined_at
      @premium_since = payload.premium_since
      @deaf = payload.deaf
      @mute = payload.mute
    end

    # :nodoc:
    def initialize(payload : Gateway::PresenceUpdatePayload)
      @user = User.new(payload.user)
      # Presence updates have no joined_at or deaf/mute, thanks Discord
    end

    # Produces a string to mention this member in a message
    def mention
      if nick
        "<@!#{user.id}>"
      else
        "<@#{user.id}>"
      end
    end
  end

  struct PartialGuildMember
    include JSON::Serializable

    property nick : String?
    property roles : Array(Snowflake)
    @[JSON::Field(converter: Discord::TimestampConverter)]
    property joined_at : Time
    @[JSON::Field(converter: Discord::MaybeTimestampConverter)]
    property premium_since : Time?
    property deaf : Bool
    property mute : Bool
    property communication_disabled_until : Time?
  end

  struct Integration
    include JSON::Serializable

    property id : Snowflake
    property name : String
    property type : String
    property enabled : Bool
    property syncing : Bool
    property role_id : Snowflake
    @[JSON::Field(key: "expire_behavior")]
    property expire_behaviour : UInt8
    property expire_grace_period : Int32
    property user : User
    property account : IntegrationAccount
    @[JSON::Field(converter: Time::EpochConverter)]
    property synced_at : Time

    {% unless flag?(:correct_english) %}
      def expire_behavior
        expire_behaviour
      end
    {% end %}
  end

  struct IntegrationAccount
    include JSON::Serializable

    property id : String
    property name : String
  end

  struct Emoji
    include JSON::Serializable

    property id : Snowflake?
    property name : String
    property roles : Array(Snowflake)?
    property require_colons : Bool?
    property managed : Bool?
    property animated : Bool?

    # Produces a CDN URL to this emoji's image in the given `size`. Will return
    # a PNG, or GIF if the emoji is animated.
    def image_url(size : Int32 = 128)
      if animated
        image_url(:gif, size)
      else
        image_url(:png, size)
      end
    end

    # Produces a CDN URL to this emoji's image in the given `format` and `size`
    # or `nil` if the emoji has no id.
    def image_url(format : CDN::CustomEmojiFormat, size : Int32 = 128)
      if emoji_id = id
        CDN.custom_emoji(emoji_id, format, size)
      end
    end

    # Produces a string to mention this emoji in a message
    def mention
      if animated
        "<a:#{name}:#{id}>"
      else
        "<:#{name}:#{id}>"
      end
    end
  end

  struct Role
    include JSON::Serializable

    property id : Snowflake
    property name : String
    property permissions : Permissions
    @[JSON::Field(key: "color")]
    property colour : UInt32
    property hoist : Bool
    property position : Int32
    property managed : Bool
    property mentionable : Bool

    @[JSON::Field(converter: Discord::RoleTags)]
    property tags : RoleTags?

    {% unless flag?(:correct_english) %}
      def color
        colour
      end
    {% end %}

    # Produces a string to mention this role in a message
    def mention
      "<@&#{id}>"
    end
  end

  struct RoleTags
    include JSON::Serializable

    property bot_id : Snowflake?
    property integration_id : Snowflake?
    property premium_subscriber : Bool = false

    def initialize(@bot_id : Snowflake?, @integration_id : Snowflake?,
                   @premium_subscriber : Bool?)
    end

    # This struct requires a special parsing routine because Discord
    # decided to send dumb values for it.
    # This can be removed whenever premium_subscriber doesnt return only null.
    def self.from_json(pull : JSON::PullParser)
      bot_id = nil
      integration_id = nil
      premium_subscriber = false

      pull.read_object do |key|
        case key
        when "bot_id"         then bot_id = Snowflake.new(pull)
        when "integration_id" then integration_id = Snowflake.new(pull)
        when "premium_subscriber"
          premium_subscriber = true
          pull.skip
        else
          pull.skip
        end
      end

      RoleTags.new(bot_id, integration_id, premium_subscriber)
    end
  end

  struct GuildBan
    include JSON::Serializable

    property user : User
    property reason : String?
  end

  struct GamePlaying
    include JSON::Serializable

    enum Type : UInt8
      Playing   = 0
      Streaming = 1
      Listening = 2
      Watching  = 3
      Custom    = 4
      Competing = 5
    end

    property name : String?
    @[JSON::Field(converter: Enum::ValueConverter(Discord::GamePlaying::Type))]
    property type : Type?
    property url : String?
    property state : String?
    property emoji : Emoji?

    def initialize(
      @name = nil,
      @type : Type? = nil,
      @url = nil,
      @state = nil,
      @emoji = nil
    )
    end
  end

  struct Presence
    include JSON::Serializable

    property user : PartialUser
    property game : GamePlaying?
    property status : String
    property activities : Array(GamePlaying)
  end

  struct GuildScheduledEvent
    include JSON::Serializable

    enum PrivacyLevel : UInt8
      GUILD_ONLY = 2

      def to_json(json : JSON::Builder)
        json.number(value)
      end
    end

    enum Status : UInt8
      SCHEDULED = 1
      ACTIVE    = 2
      COMPLETED = 3
      CANCELLED = 4

      def to_json(json : JSON::Builder)
        json.number(value)
      end
    end

    enum EntityType : UInt8
      STAGE_INSTANCE = 1
      VOICE          = 2
      EXTERNAL       = 3

      def to_json(json : JSON::Builder)
        json.number(value)
      end
    end

    struct EntityMetadata
      include JSON::Serializable

      property location : String?

      def initialize(@location)
      end
    end

    struct EventUser
      include JSON::Serializable

      property guild_scheduled_event_id : Snowflake
      property user : User
      property member : GuildMember?
    end

    property id : Snowflake
    property guild_id : Snowflake
    property channel_id : Snowflake?
    property creator_id : Snowflake?
    property name : String
    property description : String?
    @[JSON::Field(converter: Discord::TimestampConverter)]
    property scheduled_start_time : Time
    @[JSON::Field(converter: Discord::MaybeTimestampConverter)]
    property scheduled_end_time : Time?
    @[JSON::Field(converter: Enum::ValueConverter(Discord::GuildScheduledEvent::PrivacyLevel))]
    property privacy_level : PrivacyLevel
    @[JSON::Field(converter: Enum::ValueConverter(Discord::GuildScheduledEvent::Status))]
    property status : Status
    @[JSON::Field(converter: Enum::ValueConverter(Discord::GuildScheduledEvent::EntityType))]
    property entity_type : EntityType
    property entity_id : Snowflake?
    property entity_metadata : EntityMetadata
    property creator : User?
    property user_count : Int32?
  end
end
