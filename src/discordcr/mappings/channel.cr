require "./converters"

module Discord
  struct Channel
    include JSON::Serializable

    property id : Snowflake
    @[JSON::Field(converter: Enum::ValueConverter(Discord::ChannelType))]
    property type : ChannelType
    property guild_id : Snowflake?
    property position : Int32?
    property permission_overwrites : Array(Overwrite)?
    property name : String?
    property topic : String?
    property nsfw : Bool?
    property last_message_id : Snowflake?
    property bitrate : UInt32?
    property user_limit : UInt32?
    property rate_limit_per_user : UInt32?
    property recipients : Array(User)?
    property icon : String?
    property owner_id : Snowflake?
    property application_id : Snowflake?
    property parent_id : Snowflake?
    @[JSON::Field(converter: Discord::MaybeTimestampConverter)]
    property last_pin_timestamp : Time?
    property rtc_region : String?
    @[JSON::Field(converter: Enum::ValueConverter(Discord::VideoQualityMode))]
    property video_quality_mode : VideoQualityMode?
    property message_count : UInt32?
    property member_count : UInt32?

    # Produces a string to mention this channel in a message
    def mention
      "<##{id}>"
    end

    # :nodoc:
    def initialize(private_channel : PrivateChannel)
      @id = private_channel.id
      @type = private_channel.type
      @recipients = private_channel.recipients
      @last_message_id = private_channel.last_message_id
    end
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
  end

  enum VideoQualityMode
    Auto = 1
    Full = 2
  end

  # Aka DM Channel
  struct PrivateChannel
    include JSON::Serializable

    property id : Snowflake
    @[JSON::Field(converter: Enum::ValueConverter(Discord::ChannelType))]
    property type : ChannelType
    property recipients : Array(User)
    property last_message_id : Snowflake?
    property name : String?
    property icon : String?
  end

  class Message
    include JSON::Serializable

    property id : Snowflake
    property channel_id : Snowflake
    property guild_id : Snowflake?
    property author : User
    # Member object, without the user field, is only present on MESSAGE_CREATE and MESSAGE_UPDATE events
    property member : GuildMember?
    property content : String
    @[JSON::Field(converter: Discord::TimestampConverter)]
    property timestamp : Time
    @[JSON::Field(converter: Discord::MaybeTimestampConverter)]
    property edited_timestamp : Time?
    property tts : Bool
    property mention_everyone : Bool
    property mentions : Array(User)
    property mention_roles : Array(Snowflake)
    property mention_channels : Array(ChannelMention)?
    property attachments : Array(Attachment)
    property embeds : Array(Embed)
    property reactions : Array(Reaction)?
    property nonce : String | Int64?
    property pinned : Bool
    property webhook_id : Snowflake?
    @[JSON::Field(converter: Enum::ValueConverter(Discord::MessageType))]
    property type : MessageType
    property activity : MessageActivity?
    property application : Application?
    property application_id : Snowflake?
    property message_reference : MessageReference?
    @[JSON::Field(converter: Enum::ValueConverter(Discord::MessageFlags))]
    property flags : MessageFlags?
    property stickers : Array(Sticker)?
    property referenced_message : Message? # This property forces Message to be a class because of the inability to create a recursive struct
    property interaction : MessageInteraction?
    property components : Array(Component)?
  end

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
    GuildDiscoveryGracePeriodInitialWarning = 16
    GuildDiscoveryGracePeriodFinalWarning   = 17
    ThreadCreated                           = 18
    Reply                                   = 19
    ApplicationCommand                      = 20
    ThreadStarterMessage                    = 21
    GuildInviteReminder                     = 22
  end

  struct MessageActivity
    include JSON::Serializable

    @[JSON::Field(converter: Enum::ValueConverter(Discord::MessageActivityType))]
    property type : MessageActivityType
    property party_id : String?
  end

  enum MessageActivityType : UInt8
    Join        = 1
    Spectate    = 2
    Listen      = 3
    JoinRequest = 5
  end

  @[Flags]
  enum MessageFlags
    Crossposted          = 1 << 0
    IsCrosspost          = 1 << 1
    SupressEmbeds        = 1 << 2
    SourceMessageDeleted = 1 << 3
    Urgent               = 1 << 4
    HasThread            = 1 << 5
    Ephemeral            = 1 << 6
    Loading              = 1 << 7
  end

  struct Sticker
    include JSON::Serializable

    property id : Snowflake
    property pack_id : Snowflake
    property name : String
    property description : String
    property tags : String?
    property asset : String
    @[JSON::Field(converter: Enum::ValueConverter(Discord::StickerFormatType))]
    property format_type : StickerFormatType
  end

  enum StickerFormatType
    PNG    = 1
    APNG   = 2
    LOTTIE = 3
  end

  struct MessageReference
    include JSON::Serializable

    property message_id : Snowflake?
    property channel_id : Snowflake?
    property guild_id : Snowflake?
    property fail_if_not_exists : Bool?

    def initialize(@message_id = nil, @channel_id = nil, @guild_id = nil, @fail_if_not_exists = nil)
    end
  end

  struct FollowedChannel
    include JSON::Serializable

    property channel_id : Snowflake
    property webhook_id : Snowflake
  end

  struct Reaction
    include JSON::Serializable

    property count : UInt32
    property me : Bool
    property emoji : Emoji
  end

  struct Overwrite
    include JSON::Serializable

    property id : Snowflake
    @[JSON::Field(converter: Enum::ValueConverter(Discord::OverwriteType))]
    property type : OverwriteType
    property allow : Permissions
    property deny : Permissions
  end

  enum OverwriteType
    Role   = 0
    Member = 1
  end

  # There is an additional limit for the "embed" as a whole, of 6000 characters
  struct Embed
    include JSON::Serializable

    # Limit of 256 characters
    property title : String?
    property type : String?
    # Limit of 2048 characters
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
    # Limit of up to 25 fields
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

  {% for type in ["Thumbnail", "Video", "Image"] %}
  struct Embed{{ type.id }}
    include JSON::Serializable

    property url : String?
    property proxy_url : String?
    property height : UInt32?
    property width : UInt32?

    def initialize(@url = nil, @proxy_url = nil, @height = nil, @width = nil)
    end
  end
  {% end %}

  struct EmbedProvider
    include JSON::Serializable

    property name : String?
    property url : String?

    def initialize(@name = nil, @url = nil)
    end
  end

  struct EmbedAuthor
    include JSON::Serializable

    # Limit of 256 characters
    property name : String?
    property url : String?
    property icon_url : String?
    property proxy_icon_url : String?

    def initialize(@name = nil, @url = nil, @icon_url = nil)
    end
  end

  struct EmbedFooter
    include JSON::Serializable

    # Limit of 2048 characters
    property text : String
    property icon_url : String?
    property proxy_icon_url : String?

    def initialize(@text, @icon_url = nil, @proxy_icon_url = nil)
    end
  end

  struct EmbedField
    include JSON::Serializable

    # Limit of 256 characters
    property name : String
    # Limit of 1024 characters
    property value : String
    property inline : Bool?

    def initialize(@name, @value, @inline = nil)
    end
  end

  struct Attachment
    include JSON::Serializable

    property id : Snowflake
    property filename : String
    property content_type : String?
    property size : UInt32
    property url : String
    property proxy_url : String
    property height : UInt32?
    property width : UInt32?
  end

  struct ChannelMention
    include JSON::Serializable

    property id : Snowflake
    property guild_id : Snowflake
    @[JSON::Field(converter: Enum::ValueConverter(Discord::ChannelType))]
    property type : ChannelType
    property name : String
  end

  struct AllowedMentions
    include JSON::Serializable

    property parse : Array(String)
    property roles : Array(Snowflake)
    property users : Array(Snowflake)
    property replied_user : Bool

    def initialize(@parse = [] of String, @roles = [] of Snowflake, @users = [] of Snowflake, @replied_user = false)
    end
  end
end
