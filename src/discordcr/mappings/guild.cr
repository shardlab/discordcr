module Discord
  # Guilds in Discord represent an isolated collection of users and channels, and are often referred to as "servers" in the UI.
  abstract struct GuildAbstract
    include JSON::Serializable
    include AbstractCast

    property id : Snowflake
    property name : String
    property icon : String?
    property icon_hash : String?
    property splash : String?
    property discovery_splash : String?
    property owner_id : Snowflake
    property region : String
    property afk_channel_id : Snowflake?
    property afk_timeout : Int32?
    property widget_enabled : Bool?
    property widget_channel_id : Snowflake?
    @[JSON::Field(converter: Enum::ValueConverter(Discord::VerificationLevel))]
    property verification_level : VerificationLevel
    @[JSON::Field(converter: Enum::ValueConverter(Discord::MessageNotificationLevel))]
    property default_message_notifications : MessageNotificationLevel
    @[JSON::Field(converter: Enum::ValueConverter(Discord::ExplicitContentFilter))]
    property explicit_content_filter : ExplicitContentFilter
    property roles : Array(Role)
    @[JSON::Field(key: "emojis")]
    property emoji : Array(Emoji)
    property features : Array(String)
    @[JSON::Field(converter: Enum::ValueConverter(Discord::MFALevel))]
    property mfa_level : MFALevel
    property application_id : Snowflake?
    property system_channel_id : Snowflake?
    @[JSON::Field(converter: Enum::ValueConverter(Discord::SystemChannelFlags))]
    property system_channel_flags : SystemChannelFlags
    property rules_channel_id : Snowflake?
    property max_presences : UInt32?
    property max_members : UInt32?
    property vanity_url_code : String?
    property description : String?
    property banner : String?
    property premium_tier : UInt8
    property premium_subscription_count : UInt8?
    property preferred_locale : String
    property public_updates_channel_id : Snowflake?
    property max_video_channel_users : UInt32?
    property approximate_member_count : UInt32?
    property approximate_presence_count : UInt32?
    property welcome_screen : WelcomeScreen?
    @[JSON::Field(converter: Enum::ValueConverter(Discord::NSFWLevel))]
    property nsfw_level : NSFWLevel

    {% unless flag?(:correct_english) %}
      def emojis
        emoji
      end
    {% end %}

    # Produces a CDN URL to this guild's icon in the given `format` and `size`,
    # or `nil` if no icon is set.
    def icon_url(format : CDN::ExtraImageFormat = CDN::ExtraImageFormat::WebP, size : Int32 = 128)
      if icon = @icon
        CDN.guild_icon(id, icon, format, size)
      end
    end

    # Produces a CDN URL to this guild's splash in the given `format` and `size`,
    # or `nil` if no splash is set.
    def splash_url(format : CDN::ImageFormat = CDN::ImageFormat::WebP, size : Int32 = 128)
      if splash = @splash
        CDN.guild_splash(id, splash, format, size)
      end
    end

    # Produces a CDN URL to this guild's discovery_splash in the given `format` and `size`,
    # or `nil` if no discovery_splash is set.
    def discovery_splash_url(format : CDN::ImageFormat = CDN::ImageFormat::WebP, size : Int32 = 128)
      if discovery_splash = @discovery_splash
        CDN.guild_discovery_splash(id, discovery_splash, format, size)
      end
    end

    # Produces a CDN URL to this guild's banner in the given `format` and `size`,
    # or `nil` if no banner is set.
    def banner_url(format : CDN::ImageFormat = CDN::ImageFormat::WebP, size : Int32 = 128)
      if banner = @banner
        CDN.guild_banner(id, banner, format, size)
      end
    end
  end

  struct Guild < GuildAbstract
  end

  enum MessageNotificationLevel
    AllMessages  = 0
    OnlyMentions = 1
  end

  enum ExplicitContentFilter
    Disabled            = 0
    MembersWithoutRoles = 1
    AllMembers          = 2
  end

  enum MFALevel
    None     = 0
    Elevated = 1
  end

  enum VerificationLevel
    None     = 0
    Low      = 1
    Medium   = 2
    High     = 3
    VeryHigh = 4
  end

  enum NSFWLevel
    Default       = 0
    Explicit      = 1
    Safe          = 2
    AgeRestricted = 3
  end

  @[Flags]
  enum SystemChannelFlags
    SupressJoinNotifications          = 1 << 0
    SupressPremiumSubscriptions       = 1 << 1
    SupressGuildReminderNotifications = 1 << 2
  end

  # Partial Guild object sent only on `GET /users/@me/guilds` endpoint
  struct PartialGuild
    include JSON::Serializable

    property id : String
    property name : String
    property icon : String?
    property owner : Bool
    property permissions : Permissions?
    property features : Array(String)
  end

  struct UnavailableGuild
    include JSON::Serializable

    property id : Snowflake
    property unavailable : Bool
  end

  struct GuildPreview
    include JSON::Serializable

    property id : Snowflake
    property name : String
    property icon : String?
    property splash : String?
    property discovery_splash : String?
    @[JSON::Field(key: "emojis")]
    property emoji : Array(Emoji)
    property features : Array(String)
    property approximate_member_count : UInt32
    property approximate_presence_count : UInt32
    property description : String?
  end

  # This is not documented, but derived from an example provided with the `GET /guilds/{guild.id}/widget.json` endpoint
  struct GuildWidget
    include JSON::Serializable

    property id : Snowflake
    property name : String
    property instant_invite : String
    property channels : Array(WidgetChannel)
    property members : Array(WidgetMember)
    property presence_count : UInt32
  end

  # This structure is not documented
  struct WidgetChannel
    include JSON::Serializable

    property id : Snowflake
    property name : String
    property position : UInt32
  end

  # This structure is not documented
  struct WidgetMember
    include JSON::Serializable

    property id : Snowflake
    property username : String
    property discriminator : String
    property avatar : String?
    property status : String
    property avatar_url : String
  end

  # In the docs this is called GuildWidget but this is not the widget itself
  struct GuildWidgetSettings
    include JSON::Serializable

    property enabled : Bool
    property channel_id : Snowflake?
  end

  abstract struct GuildMemberAbstract
    include JSON::Serializable
    include AbstractCast

    property user : User?
    property nick : String?
    property roles : Array(Snowflake)
    @[JSON::Field(converter: Discord::TimestampConverter)]
    property joined_at : Time
    @[JSON::Field(converter: Discord::MaybeTimestampConverter)]
    property premium_since : Time?
    property deaf : Bool?
    property mute : Bool?
    property pending : Bool?
    property permissions : Permissions?

    # Produces a string to mention this member in a message
    def mention
      if nick
        "<@!#{user.id}>"
      else
        "<@#{user.id}>"
      end
    end
  end

  struct GuildMember < GuildMemberAbstract
    # :nodoc:
    def initialize(user : User, partial_member : GuildMember)
      @user = user
      @roles = partial_member.roles
      @nick = partial_member.nick
      @joined_at = partial_member.joined_at
      @premium_since = partial_member.premium_since
      @mute = partial_member.mute
      @deaf = partial_member.deaf
      @joined_at = partial_member.joined_at
    end

    # :nodoc:
    def initialize(payload : GuildMemberAbstract, roles : Array(Snowflake), nick : String?)
      initialize(payload)
      @nick = nick
      @roles = roles
    end

    # :nodoc:
    def initialize(payload : Gateway::PresenceUpdatePayload)
      @user = User.new(payload.user)
      @roles = Array(Snowflake).new
      @joined_at = Time.utc
      @mute = false
      @deaf = false
      # Presence updates have no joined_at or deaf/mute, thanks Discord
      # And since API v8 there is no nick or roles! Thanks Discord!!
    end
  end

  abstract struct IntegrationAbstract
    include JSON::Serializable
    include AbstractCast

    property id : Snowflake
    property name : String
    property type : String
    property enabled : Bool = true # Because AuditLog object holds an array of partial integration objects without the enabled field, we will assume true if it is not present
    property syncing : Bool?
    property role_id : Snowflake?
    property enable_emoticons : Bool?
    @[JSON::Field(key: "expire_behavior", converter: Enum::ValueConverter(Discord::ExpireBehaviour))]
    property expire_behaviour : ExpireBehaviour?
    property expire_grace_period : UInt32?
    property user : User?
    property account : IntegrationAccount
    @[JSON::Field(converter: Discord::MaybeTimestampConverter)]
    property synced_at : Time?
    property subscriber_count : UInt32?
    property revoked : Bool?
    property application : IntegrationApplication?

    {% unless flag?(:correct_english) %}
      def expire_behavior
        expire_behaviour
      end
    {% end %}
  end

  struct Integration < IntegrationAbstract
  end

  enum ExpireBehaviour
    RemoveRole = 0
    Kick       = 1
  end

  struct IntegrationAccount
    include JSON::Serializable

    property id : String
    property name : String
  end

  struct IntegrationApplication
    include JSON::Serializable

    property id : Snowflake
    property name : String
    property icon : String?
    property description : String
    property summary : String
    property bot : User?
  end

  struct GuildBan
    include JSON::Serializable

    property reason : String?
    property user : User
  end

  struct WelcomeScreen
    include JSON::Serializable

    property description : String?
    property welcome_channels : Array(WelcomChannel)
  end

  struct WelcomChannel
    include JSON::Serializable

    property channel_id : Snowflake
    property description : String
    property emoji_id : Snowflake?
    property emoji_name : String?
  end
end
