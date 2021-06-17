module Discord
  struct User
    include JSON::Serializable

    property id : Snowflake
    property username : String
    property discriminator : String
    property avatar : String?
    property bot : Bool?
    property system : Bool?
    property mfa_enabled : Bool?
    property locale : String?
    property verified : Bool?
    property email : String?
    @[JSON::Field(converter: Enum::ValueConverter(Discord::UserFlags))]
    property flags : UserFlags?
    @[JSON::Field(converter: Enum::ValueConverter(Discord::PremiumType))]
    property premium_type : PremiumType?
    @[JSON::Field(converter: Enum::ValueConverter(Discord::UserFlags))]
    property public_flags : UserFlags?

    # :nodoc:
    def initialize(partial : PartialUser)
      @username = partial.username.not_nil!
      @id = partial.id
      @discriminator = partial.discriminator.not_nil!
      @avatar = partial.avatar
      @email = partial.email
      @bot = partial.bot
    end

    # Produces a CDN URL to this user's avatar in the given `size`.
    # If the user has an avatar a WebP will be returned, or a GIF
    # if the avatar is animated. If the user has no avatar, a default
    # avatar URL is returned.
    def avatar_url(size : Int32 = 128)
      if avatar = @avatar
        CDN.user_avatar(id, avatar, size)
      else
        CDN.default_user_avatar(discriminator)
      end
    end

    # Produces a CDN URL to this user's avatar, in the given `format` and
    # `size`. If the user has no avatar, a default avatar URL is returned.
    def avatar_url(format : CDN::ExtraImageFormat, size : Int32 = 128)
      if avatar = @avatar
        CDN.user_avatar(id, avatar, format, size)
      else
        CDN.default_user_avatar(discriminator)
      end
    end

    # Produces a string to mention this user in a message
    def mention
      "<@#{id}>"
    end
  end

  @[Flags]
  enum UserFlags : UInt32
    DiscordEmployee           = 1 << 0
    PartneredServerOwner      = 1 << 1
    HypeSquadEvents           = 1 << 2
    BugHunterLevel1           = 1 << 3
    HouseBravery              = 1 << 6
    HouseBrilliance           = 1 << 7
    HouseBalance              = 1 << 8
    EarlySupporter            = 1 << 9
    TeamUser                  = 1 << 10
    System                    = 1 << 12
    BugHunterLevel2           = 1 << 14
    VerifiedBot               = 1 << 16
    EarlyVerifiedBotDeveloper = 1 << 17
    DiscordCertifiedModerator = 1 << 18
  end

  enum PremiumType
    None         = 0
    NitroClassic = 1
    Nitro        = 2
  end

  # NOTE: Only exists for the sake of Presence and old code
  struct PartialUser
    include JSON::Serializable

    property username : String?
    property id : Snowflake
    property discriminator : String?
    property avatar : String?
    property email : String?
    property bot : Bool?
    @[JSON::Field(converter: Enum::ValueConverter(Discord::UserFlags))]
    property flags : UserFlags?

    def full? : Bool
      !@username.nil? && !@discriminator.nil? && !@avatar.nil?
    end
  end

  struct Connection
    include JSON::Serializable

    property id : Snowflake
    property name : String
    property type : String
    property revoked : Bool
    property integrations : Array(Integration)?
    property verified : Bool
    property friend_sync : Bool
    property show_activity : Bool
    @[JSON::Field(converter: Enum::ValueConverter(Discord::Visibility))]
    property visibility : Visibility
  end

  enum Visibility
    None     = 0
    Everyone = 1
  end
end
