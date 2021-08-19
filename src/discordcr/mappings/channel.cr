require "./converters"

module Discord
  enum MessageType : UInt8
    Default                                 =  0
    RecipientAdd                            =  1
    RecipientRemove                         =  2
    Call                                    =  3
    ChannelNameChange                       =  4
    ChannelIconChange                       =  5
    ChannelPinnedMessage                    =  6
    GuildMemberJoin                         =  7
    UserPremiumGuildSubscription            =  8
    UserPremiumGuildSubscriptionTier1       =  9
    UserPremiumGuildSubscriptionTier2       = 10
    UserPremiumGuildSubscriptionTier3       = 11
    ChannelFollowAdd                        = 12
    GuildDiscoveryDisqualified              = 14
    GuildDiscoveryRequalified               = 15
    GuildDiscoveryGracePeriodInitialWarning = 16
    GuildDiscoveryGracePeriodFinalWarning   = 17
    ThreadCreated                           = 18
    Reply                                   = 19
    ApplicationCommand                      = 20
    ThreadStarterMessage                    = 21
    GuildInviteReminder                     = 22

    def self.new(pull : JSON::PullParser)
      MessageType.new(pull.read_int.to_u8)
    end
  end

  enum AutoArchiveDuration : UInt16
    Hour      =    60
    Day       =  1440
    ThreeDays =  4320
    Week      = 10080

    def to_json(json : JSON::Builder)
      json.number(value)
    end

    def self.new(pull : JSON::PullParser)
      AutoArchiveDuration.new(pull.read_int.to_u16)
    end
  end

  class Message
    include JSON::Serializable

    property type : MessageType
    property content : String
    property id : Snowflake
    property channel_id : Snowflake
    property guild_id : Snowflake?
    property author : User
    property member : PartialGuildMember?
    @[JSON::Field(converter: Discord::TimestampConverter)]
    property timestamp : Time
    property tts : Bool
    property mention_everyone : Bool
    property mentions : Array(User)
    property mention_roles : Array(Snowflake)
    property attachments : Array(Attachment)
    property embeds : Array(Embed)
    property pinned : Bool?
    property reactions : Array(Reaction)?
    property nonce : String | Int64?
    property activity : Activity?
    property webhook_id : Snowflake?
    property thread : Channel?
    property referenced_message : Message?

    def to_message_reference : MessageReference
      MessageReference.new(@id, @channel_id, @guild_id)
    end
  end

  struct MessageReference
    include JSON::Serializable

    property message_id : Snowflake?
    property channel_id : Snowflake?
    property guild_id : Snowflake?
    property fail_if_not_exists : Bool?

    def initialize(@message_id = nil, @channel_id = nil,
                   @guild_id = nil, @fail_if_not_exists = nil)
    end
  end

  enum ActivityType : UInt8
    Join        = 1
    Spectate    = 2
    Listen      = 3
    JoinRequest = 5

    def self.new(pull : JSON::PullParser)
      ActivityType.new(pull.read_int.to_u8)
    end
  end

  struct Activity
    include JSON::Serializable

    property type : ActivityType
    property party_id : String?
  end

  enum ChannelType : UInt8
    GuildText          =  0
    DM                 =  1
    GuildVoice         =  2
    GroupDM            =  3
    GuildCategory      =  4
    GuildNews          =  5
    GuildStore         =  6
    GuildNewsThread    = 10
    GuildPublicThread  = 11
    GuildPrivateThread = 12
    GuildStageVoice    = 13

    def self.new(pull : JSON::PullParser)
      ChannelType.new(pull.read_int.to_u8)
    end
  end

  struct Channel
    include JSON::Serializable

    property id : Snowflake
    property type : ChannelType
    property guild_id : Snowflake?
    property name : String?
    property permission_overwrites : Array(Overwrite)?
    property topic : String?
    property last_message_id : Snowflake?
    property bitrate : UInt32?
    property user_limit : UInt32?
    property recipients : Array(User)?
    property nsfw : Bool?
    property icon : String?
    property owner_id : Snowflake?
    property application_id : Snowflake?
    property position : Int32?
    property parent_id : Snowflake?
    property rate_limit_per_user : Int32?
    property thread_metadata : ThreadMetaData?
    property message_count : UInt32?
    property member_count : UInt32?
    property member : ThreadMember?
    property last_message_id : Snowflake?

    # :nodoc:
    def initialize(private_channel : PrivateChannel)
      @id = private_channel.id
      @type = private_channel.type
      @recipients = private_channel.recipients
      @last_message_id = private_channel.last_message_id
    end

    # Produces a string to mention this channel in a message
    def mention
      "<##{id}>"
    end
  end

  struct ThreadMetaData
    include JSON::Serializable
    property archived : Bool
    property auto_archive_duration : AutoArchiveDuration
    property archive_timestamp : Time
    property locked : Bool
    property invitable : Bool?
  end

  enum StagePrivacyLevel : UInt8
    PUBLIC     = 1
    GUILD_ONLY = 2

    def self.new(pull : JSON::PullParser)
      StagePrivacyLevel.new(pull.read_int.to_u8)
    end

    def to_json(json : JSON::Builder)
      json.number(value)
    end
  end

  struct StageInstance
    include JSON::Serializable

    getter id : Snowflake
    getter guild_id : Snowflake
    getter channel_id : Snowflake
    getter topic : String
    getter privacy_level : StagePrivacyLevel
    getter discoverable_disabled : Bool
  end

  struct PrivateChannel
    include JSON::Serializable

    property id : Snowflake
    property type : ChannelType
    property recipients : Array(User)
    property last_message_id : Snowflake?
  end

  struct Overwrite
    include JSON::Serializable

    property id : Snowflake
    property type : Int8
    property allow : Permissions
    property deny : Permissions
  end

  struct Reaction
    include JSON::Serializable

    property emoji : ReactionEmoji
    property count : UInt32
    property me : Bool
  end

  struct ReactionEmoji
    include JSON::Serializable

    property id : Snowflake?
    property name : String
  end

  struct Embed
    include JSON::Serializable

    property title : String?
    property type : String
    property description : String?
    property url : String?
    @[JSON::Field(converter: Discord::MaybeTimestampConverter)]
    property timestamp : Time?
    @[JSON::Field(key: "color")]
    property colour : UInt32?
    property footer : EmbedFooter?
    property image : EmbedImage?
    property thumbnail : EmbedThumbnail?
    property video : EmbedVideo?
    property provider : EmbedProvider?
    property author : EmbedAuthor?
    property fields : Array(EmbedField)?

    def initialize(@title : String? = nil, @type : String = "rich",
                   @description : String? = nil, @url : String? = nil,
                   @timestamp : Time? = nil, @colour : UInt32? = nil,
                   @footer : EmbedFooter? = nil, @image : EmbedImage? = nil,
                   @thumbnail : EmbedThumbnail? = nil, @author : EmbedAuthor? = nil,
                   @fields : Array(EmbedField)? = nil)
    end

    {% unless flag?(:correct_english) %}
      def color
        colour
      end
    {% end %}
  end

  struct EmbedThumbnail
    include JSON::Serializable

    property url : String
    property proxy_url : String?
    property height : UInt32?
    property width : UInt32?

    def initialize(@url : String)
    end
  end

  struct EmbedVideo
    include JSON::Serializable

    property url : String
    property height : UInt32
    property width : UInt32
  end

  struct EmbedImage
    include JSON::Serializable

    property url : String
    property proxy_url : String?
    property height : UInt32?
    property width : UInt32?

    def initialize(@url : String)
    end
  end

  struct EmbedProvider
    include JSON::Serializable

    property name : String
    property url : String?
  end

  struct EmbedAuthor
    include JSON::Serializable

    property name : String?
    property url : String?
    property icon_url : String?
    property proxy_icon_url : String?

    def initialize(
      @name : String? = nil,
      @url : String? = nil,
      @icon_url : String? = nil
    )
    end
  end

  struct EmbedFooter
    include JSON::Serializable

    property text : String?
    property icon_url : String?
    property proxy_icon_url : String?

    def initialize(
      @text : String? = nil,
      @icon_url : String? = nil
    )
    end
  end

  struct EmbedField
    include JSON::Serializable

    property name : String
    property value : String
    property inline : Bool

    def initialize(
      @name : String,
      @value : String,
      @inline : Bool = false
    )
    end
  end

  struct Attachment
    include JSON::Serializable

    property id : Snowflake
    property filename : String
    property size : UInt32
    property url : String
    property proxy_url : String
    property height : UInt32?
    property width : UInt32?
  end

  struct ThreadMember
    include JSON::Serializable

    property id : Snowflake?
    property user_id : Snowflake?
    property join_timestamp : Time
    property flags : UInt32
  end
end
